require_relative './gitlab_client.rb'
require_relative './highline_cli.rb'

module GitHelper
  class GitLabMergeRequest

    #######################
    ### BASIC FUNCTIONS ###
    #######################

    def create
      begin
        # Ask these questions right away
        base_branch
        new_mr_title
        options = {
          source_branch: local_branch,
          target_branch: base_branch,
          description: new_mr_body
        }

        puts "Creating merge request: #{new_mr_title}"
        mr = gitlab_client.create_merge_request(local_project, new_mr_title, options)

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
        merge = gitlab_client.accept_merge_request(local_project, mr_id, options)
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

    #################################
    ### ABOUT THE LOCAL CODE BASE ###
    #################################

    private def local_project
      @local_project ||= local_code.name
    end

    private def local_branch
      @local_branch ||= local_code.branch
    end

    private def autogenerated_title
      @autogenerated_title ||= local_code.generate_title
    end

    private def default_branch
      @default_branch ||= local_code.default_branch(local_repo, gitlab_client)
    end

    private def mr_template_options
      @mr_template_options ||= local_code.template_options({
                                 nested_directory_name: "merge_request_templates",
                                 non_nested_file_name: "merge_request_template"
                               })
    end

    ###################################
    ### INTERPRETING USER'S ANSWERS ###
    ###################################

    private def mr_id
      @mr_id ||= cli.merge_request_id
    end

    private def squash_merge_request
      @squash_merge_request ||= cli.squash_merge_request?
    end

    private def remove_source_branch
      @remove_source_branch ||= cli.remove_source_branch?
    end

    private def new_mr_title
      @new_mr_title ||= if cli.accept_autogenerated_title?(autogenerated_title)
                          autogenerated_title
                        else
                          cli.title
                        end
    end

    private def base_branch
      @base_branch ||= if cli.base_branch_default?(default_branch)
                         default_branch
                       else
                         cli.base_branch
                       end
    end

    private def new_mr_body
      @new_mr_body ||= template_name_to_apply ? local_code.read_template(template_name_to_apply) : ''
    end

    private def template_name_to_apply
      return @template_name_to_apply if @template_name_to_apply
      @template_name_to_apply = nil

      unless mr_template_options.empty?
        if mr_template_options.count == 1
          apply_single_template = cli.apply_template?(mr_template_options.first)
          @template_name_to_apply = mr_template_options.first if apply_single_template
        else
          response = cli.template_to_apply(mr_template_options, 'merge')
          @template_name_to_apply = response unless response == "None"
        end
      end

      @template_name_to_apply
    end

    #############
    ### OTHER ###
    #############

    private def existing_mr_title
      @existing_mr_title ||= gitlab_client.merge_request(local_project, mr_id).title
    end

    private def gitlab_client
      @gitlab_client ||= GitHelper::GitLabClient.new.client
    end

    private def cli
      @cli ||= GitHelper::HighlineCli.new
    end

    private def local_code
      @local_code ||= GitHelper::LocalCode.new
    end
  end
end
