require 'active_support/concern'
require 'search_controller'

module RedmineElasticsearch::Patches::SearchControllerPatch
  extend ActiveSupport::Concern

  included do
    alias_method_chain :index, :elasticsearch
  end

  def index_with_elasticsearch
    @question = params[:q] || ''
    @question.strip!
    @all_words = params[:all_words] ? params[:all_words].present? : true
    @titles_only = params[:titles_only] ? params[:titles_only].present? : false

    projects_to_search =
        case params[:scope]
          when 'all'
            nil
          when 'my_projects'
            User.current.memberships.collect(&:project)
          when 'subprojects'
            @project ? (@project.self_and_descendants.active.all) : nil
          else
            @project
        end

    # quick jump to an issue
    if (m = @question.match(/^#?(\d+)$/)) && (issue = Issue.visible.find_by_id(m[1].to_i))
      redirect_to issue_path(issue)
      return
    end

    @object_types = Redmine::Search.available_search_types.dup
    if projects_to_search.is_a? Project
      # don't search projects
      @object_types.delete('projects')
      # only show what the user is allowed to view
      @object_types = @object_types.select {|o| User.current.allowed_to?("view_#{o}".to_sym, projects_to_search)}
    end

    @scope = @object_types.select {|t| params[t]}
    @scope = @object_types if @scope.empty?

    index_names = tire_index_names(@object_types)
    search = Tire::Search::Search.new(index_names, :page => params[:page] || 1)
    search.query do |query|
      query.string @question
    end
    search.facet('types'){ terms :_type }
    @results = search.results
    @results_by_type = Hash.new {|h,k| h[k] = 0}
    search.results.facets['types']['terms'].each do |facet|
      @results_by_type[facet['term']] = facet['count']
    end

    render :layout => false if request.xhr?
  end

  private

  def tire_index_names(object_types)
    object_types.map { |object_type| object_type.classify.constantize.index_name }
  end
end

unless SearchController.included_modules.include?(RedmineElasticsearch::Patches::SearchControllerPatch)
  SearchController.send :include, RedmineElasticsearch::Patches::SearchControllerPatch
end
