#
# Cookbook Name:: rails-bootstrap
# Recipe:: default
#
# Copyright 2013, 119 Labs LLC
#
# See license.txt for details
#
class Chef::Recipe
    # mix in recipe helpers
    include Chef::RubyBuild::RecipeHelpers
end

app_dir = node['rails-lastmile']['app_dir']

include_recipe "rails-lastmile::setup"

include_recipe "nginx"
include_recipe "unicorn"

directory "/var/run/unicorn" do
  owner "root"
  group "root"
  mode "777"
  action :create
end

file "/var/run/unicorn/master.pid" do
  owner "root"
  group "root"
  mode "666"
  action :create_if_missing
end

file "/var/log/unicorn.log" do
  owner "root"
  group "root"
  mode "666"
  action :create_if_missing
end


unicorn_config "/etc/unicorn.cfg" do
  listen( { node[:unicorn][:listen] => node[:unicorn][:options] })
  pid node[:unicorn][:pid]
  working_directory app_dir
  worker_timeout node[:unicorn][:worker_timeout]
  stdout_path node[:unicorn][:stdout_path]
  stderr_path node[:unicorn][:stderr_path]
  preload_app node[:unicorn][:preload_app]
  worker_processes node[:unicorn][:worker_processes]
  before_fork node[:unicorn][:before_fork]
end

bash "change-cluster-encoding-to-utf8" do
  code <<-CODE
    pg_dropcluster --stop 9.1 main
    pg_createcluster --start -e UTF-8 9.1 main
  CODE
end

bash "create-db-user" do
  user "postgres"
  code <<-CODE
    psql -c "create user dcb with createdb login encrypted password '0rsm4smn3zz'"
  CODE
end

rbenv_script "run-rails" do
  rbenv_version node['rails-lastmile']['ruby_version']
  cwd app_dir
  if node['rails-lastmile']['reset_db']
    code <<-EOT1
      export RAILS_ENV=production >> ~/.bash_profile
      bundle install RAILS_ENV=production
      bundle exec rake db:reset RAILS_ENV=production
      bundle exec rake db:test:load RAILS_ENV=production
      ps -p `cat /var/run/unicorn/master.pid` &>/dev/null || bundle exec unicorn -c /etc/unicorn.cfg -D --env #{node['rails-lastmile']['environment']}
    EOT1
  else
    code <<-EOT2
      export RAILS_ENV=production >> ~/.bash_profile
      bundle install
      bundle exec rake db:create RAILS_ENV=production
      bundle exec rake db:migrate RAILS_ENV=production
      bundle exec rake db:test:load RAILS_ENV=production
      ps -p `cat /var/run/unicorn/master.pid` &>/dev/null || bundle exec unicorn -c /etc/unicorn.cfg -D --env #{node['rails-lastmile']['environment']}
    EOT2
  end
end

template "/etc/nginx/sites-enabled/default" do
  owner "root"
  group "root"
  mode "644"
  source "nginx.erb"
  variables( :static_root => "#{app_dir}/public")
  notifies :restart, "service[nginx]"
end

service "unicorn"
service "nginx"
