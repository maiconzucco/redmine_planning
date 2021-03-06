# Copyright 2014 Egbert van der Wal <egbert@assistobot.com>
#
# This file is part of redmine_planning
#
# redmine_planning is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_planning is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_planning. If not see <http://www.gnu.org/licenses/>.

require 'json'

class PlanningController < ApplicationController
  unloadable

  menu_item :planning
  before_filter :find_optional_project
  rescue_from Query::StatementInvalid, :with => :query_statement_invalid

  helper :gantt
  helper :issues
  helper :projects
  helper :queries
  include QueriesHelper

  def show
    Redmine::Plugin.mirror_assets(:redmine_planning)
    @planning = {month_from: 5, year_from: 2014}
    @gantt = Redmine::Helpers::Gantt.new(params)
    @gantt.project = @project
    retrieve_query
    @query.group_by = nil
    @gantt.query = @query if @query.valid?

  end

  def save
    issue_list = []
    Issue.transaction do
      params[:issues].each do |k, update|
          logger.error(update)
          issue = Issue.find(update[:id])
          issue[:start_date] = Date.parse(update[:start_date])
          issue[:due_date] = Date.parse(update[:due_date])
          issue.save!
          issue_list.push(issue)
      end
    end
    
    # Give feedback, as no errors doesn't indicate nothing changed
    response = {} 
    issue_list.each do |issue|
      # It seems that when you save an issue, the state of the object may not be
      # equal to that in the database, due to validation correction. Especially
      # for parent tasks, a reload is needed.
      issue.reload
      response[issue.id] = {start_date: issue.start_date, due_date: issue.due_date}
      
      # Add all parents as they might've been updated as well
      parent = issue.parent
      while not parent.nil? do
        response[parent.id] = {start_date: parent.start_date, due_date: parent.due_date}
        parent = parent.parent
      end
    end

    respond_to do |format|
      format.json { render json: response }
    end
  end

  def issue_compare(x, y)
    if x.root_id == y.root_id
      x.lft <=> y.lft
    else
      x.root_id <=> y.root_id
    end
  end

  def issues
    @gantt = Redmine::Helpers::Gantt.new(params)
    @gantt.project = @project
    retrieve_query
    @query.group_by = nil
    @gantt.query = @query if @query.valid?

    projects = @gantt.projects
    response = {issues: [], relations: []}
    trackers = Tracker.find(:all)

    project_ids = {}
    projects.each do |prj|
        project_ids[prj.id] = {identifier: prj.identifier, name: prj.name}
    end

    tracker_ids = {}
    trackers.each do |tracker|
        tracker_ids[tracker.id] = tracker[:name]
    end

    Project.project_tree(projects) do |project, level|
      issues = @gantt.project_issues(project)
      issues.sort! { |a, b| issue_compare(a, b) }
      issues.each do |issue|
        #issue[:start_date] = Date.new() if issue[:start_date].nil?
        #issue[:due_date] = (issue[:start_date] + 5) if issue[:due_date].nil?
        prj = project_ids[issue[:project_id]]
        tracker = tracker_ids[issue.tracker_id]
        logger.error(issue[:tracker])
        response[:issues].push({
            :id => issue[:id],
            :start_date => issue[:start_date],
            :due_date => issue[:due_date],
            :project_id => issue[:project_id],
            :project_identifier => prj[:identifier],
            :project_name => prj[:name],
            :tracker => tracker,
            :name => issue[:subject],
            :description => issue[:description],
            :leaf => issue.leaf?,
            :parent => issue.parent_issue_id
        })
      end
    end
    @gantt.relations.each do |from_relation, relations|
        relations.each do |relation|
            response[:relations].push({
                :id => relation[:id],
                :from => relation[:issue_from_id],
                :to => relation[:issue_to_id],
                :type => relation[:relation_type],
                :delay => relation[:delay]
            })
        end
    end

    respond_to do |format|
      format.json { render json: response }
    end
  end
end
