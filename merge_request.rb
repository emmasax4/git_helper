#!/usr/bin/env ruby

require_relative './gitlab_client.rb'
require_relative './highline_cli.rb'

class GitLabMergeRequest
  def create
    begin
      # Ask these questions right away
      base_branch
      new_mr_title

      puts "Creating merge request: #{new_mr_title}"
      mr = gitlab_client.create_merge_request(local_repo, new_mr_title, { source_branch: local_branch, target_branch: base_branch })

      if mr.diff_refs.base_sha == mr.diff_refs.head_sha
        puts "Merge request was created, but no commits have been pushed to GitLab: #{mr.web_url}"
      else
        puts "Merge request successfully created: #{mr.web_url}"
      end
    rescue Gitlab::Error::Conflict => e
      puts 'Could not create merge request:'
      puts '  A merge request already exists for this branch'
    rescue Exception => e
      puts 'Could not create merge request:'
      puts e.message
    end
  end

  def merge
    begin
      # Ask these questions right away
      mr_id
      options = {}
      options[:should_remove_source_branch] = remove_source_branch?
      options[:squash] = squash_merge_request?
      options[:squash_commit_message] = existing_mr_title

      puts "Merging merge request: #{mr_id}"
      merge = gitlab_client.accept_merge_request(local_repo, mr_id, options)
      puts "Merge request successfully merged: #{merge.merge_commit_sha}"
    rescue Gitlab::Error::MethodNotAllowed => e
      puts 'Could not merge merge request:'
      puts '  The merge request is not mergeable'
    rescue Gitlab::Error::NotFound => e
      puts 'Could not merge merge request:'
      puts "  Could not a locate a merge request to merge with ID #{mr_id}"
    rescue Exception => e
      puts 'Could not merge merge request:'
      puts e.message
    end
  end

  private def local_repo
    # Get the repository by looking in the remote URLs for the full repository name
    remotes = `git remote -v`
    return remotes.scan(/\S[\s]*[\S]+.com[\S]{1}([\S]*).git/).first.first
  end

  private def local_branch
    # Get the current branch by looking in the list of branches for the *
    branches = `git branch`
    return branches.scan(/\*\s([\S]*)/).first.first
  end

  private def mr_id
    @mr_id ||= cli.ask('Merge Request ID?')
  end

  private def existing_mr_title
    @existing_mr_title ||= gitlab_client.merge_request(local_repo, mr_id).title
  end

  private def new_mr_title
    @new_mr_title ||= accept_autogenerated_title? ? autogenerated_title : cli.ask('Title?')
  end

  private def base_branch
    @base_branch ||= base_branch_default? ? default_branch : cli.ask('Base branch?')
  end

  private def autogenerated_title
    @autogenerated_title ||= local_branch.split('_')[0..-1].join(' ').capitalize
  end

  private def default_branch
    @default_branch ||= gitlab_client.branches(local_repo).select { |branch| branch.default }.first.name
  end

  private def base_branch_default?
    answer = cli.ask("Is '#{default_branch}' the correct base branch for your new merge request? (y/n)")
    !!(answer =~ /^y/i)
  end

  private def accept_autogenerated_title?
    answer = cli.ask("Accept the autogenerated merge request title '#{autogenerated_title}'? (y/n)")
    !!(answer =~ /^y/i)
  end

  private def squash_merge_request?
    answer = cli.ask('Squash merge request? (y/n)')
    !!(answer =~ /^y/i)
  end

  private def remove_source_branch?
    answer = cli.ask('Remove source branch after merging? (y/n)')
    !!(answer =~ /^y/i)
  end

  private def gitlab_client
    @gitlab_client ||= GitLabClient.new.client
  end

  private def cli
    @cli ||= HighlineCli.new
  end
end

arg = ARGV[0]

case arg
when '-c', '--create'
  action = :create
when '-m', '--merge'
  action = :merge
when '-h', '--help', nil, ''
  puts """
Usage for working with this merge requests script:
  # Run this script from within your local repository/branch
  ./merge_request.rb [-h|-c|-m]

  -h, --help      - Displays this help information
  -c, --create    - Create a new merge request
  -m, --merge     - Merge an existing merge request

Required: create or merge
Examples:
  ./merge_request.rb -c
  ./merge_request.rb -m
    """
    exit(0)
end

merge_request = GitLabMergeRequest.new

case action
when :create
  merge_request.create
when :merge
  merge_request.merge
end
