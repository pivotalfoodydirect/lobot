include_recipe "pivotal_server::daemontools"
include_recipe "pivotal_ci::xvfb"
include_recipe "pivotal_ci::git_config"

username = ENV['SUDO_USER'].strip
user_home = ENV['HOME']

install_dir = "/usr/local/jenkins"
bin_location = "#{install_dir}/jenkins.war"

execute "download jenkins" do
  command "mkdir -p #{install_dir} && curl -Lsf http://mirrors.jenkins-ci.org/war/latest/jenkins.war -o #{bin_location}"
  not_if { File.exists?(bin_location) }
end

['git', 'ansicolor'].each do |plugin|
  execute "download #{plugin} plugin" do
    command "mkdir -p /home/#{username}/.jenkins/plugins && curl -Lsf http://mirrors.jenkins-ci.org/plugins/#{plugin}/latest/#{plugin}.hpi -o /home/#{username}/.jenkins/plugins/#{plugin}.hpi"
    not_if { File.exists?("/home/#{username}/.jenkins/plugins/#{plugin}.hpi") }
    user username
  end
end

execute "make project dir" do
  command "mkdir -p /home/#{username}/.jenkins/jobs/#{ENV['APP_NAME']}"
  user username
end

template "/home/#{username}/.jenkins/jobs/#{ENV['APP_NAME']}/config.xml" do
  source "jenkins-job-config.xml.erb"
  owner username
  notifies :run, "execute[reload jenkins]"
  variables(
    :git_location => CI_CONFIG['git_location'],
    :build_command => CI_CONFIG['build_command']
  )
end

(CI_CONFIG['additional_builds'] || []).each do |build|
  execute "make project dir" do
    command "mkdir -p /home/#{username}/.jenkins/jobs/#{build['build_name']}"
    user username
  end

  template "/home/#{username}/.jenkins/jobs/#{build['build_name']}/config.xml" do
    source "jenkins-job-config.xml.erb"
    owner username
    notifies :run, "execute[reload jenkins]"
    variables(
      :git_location => build['git_location'],
      :build_command => build['build_script']
    )
  end
end

service_name = "jenkins"

execute "create daemontools directory" do
  command "mkdir -p /service/#{service_name}"
end

execute "create run script2" do # srsly! the not_if from mysql was being applied because they had the same name. I kid you not.
  command "echo -e '#!/bin/sh\nexport PATH=/usr/lib64/qt4/bin/:usr/local/mysql/bin/:$PATH\nexport HOME=/home/#{username}\nexec /command/setuidgid #{username}  /usr/bin/java -jar #{bin_location}' > /service/#{service_name}/run"
  # not_if "ls /service/#{service_name}/run"
end

execute "make run script executable" do
  command "chmod 755 /service/#{service_name}/run"
end

execute "reload jenkins" do
  command "sudo svc -h /service/jenkins/"
  action :nothing
end