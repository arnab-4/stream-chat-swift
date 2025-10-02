# frozen_string_literal: true

source 'https://rubygems.org'

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

gem 'cocoapods', '>= 1.12.1'
gem 'danger'
gem 'danger-commit_lint'
gem 'fastlane', '>= 2.212.0'
gem 'fastlane-plugin-lizard'
gem 'jazzy'
gem 'json'
gem 'plist'
gem 'rubocop', '1.66.0'
gem 'rubocop-performance', '>= 1.16.0'
gem 'rubocop-require_tools'
gem 'sinatra', '>= 4.0.0'
gem 'slather'
gem 'stream-chat-ruby', '3.0.0'
gem 'xcode-install'
gem 'xctest_list'

plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
