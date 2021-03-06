require 'puppet'
require 'net/http'
require 'json'

Puppet::Type.type(:git_deploy_key).provide(:gitlab) do

  defaultfor :gitlab => :exists

  def git_server
    return resource[:server_url].strip unless resource[:server_url].nil?
    return 'https://gitlab.com'
  end

  def api_call(action,url,data = nil)
    uri = URI.parse(url)

    http = Net::HTTP.new(uri.host, uri.port)

    if uri.port == 443
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    else
      http.use_ssl = false
    end

    #http.set_debug_output($stdout)

    if action =~ /post/i
      req = Net::HTTP::Post.new(uri.request_uri)
    elsif action =~ /put/i
      req = Net::HTTP::Put.new(uri.request_uri)
    elsif action =~ /delete/i
      req = Net::HTTP::Delete.new(uri.request_uri)
    else
      req = Net::HTTP::Get.new(uri.request_uri)
    end

    #req.initialize_http_header({'Accept' => 'application/vnd.github.v3+json', 'User-Agent' => 'puppet-gms'})
    req.set_content_type('application/json')
    #req.add_field('Authorization', "token #{resource[:token].strip}")
    req.add_field('PRIVATE-TOKEN', resource[:token])

    if data
      req.body = data.to_json
    end

    http.request(req)
  end

  def exists?
    project_id = get_project_id

    sshkey_hash = Hash.new
    url = "#{git_server}/api/v3/projects/#{project_id}/keys"

    response = api_call('GET', url)

    sshkey_json = JSON.parse(response.body)
    sshkey_json.each do |child|
      sshkey_hash[child['key']] = child['id']
    end

    sshkey_hash.keys.each do |k|
      if k.eql?(File.read(resource[:path]).strip)
        return true
      end
    end

    return false
  end

  def get_project_id
    return resource[:project_id].to_i unless resource[:project_id].nil?

    if resource[:project_name].nil?
      raise(Puppet::Error, "git_deploy_key: Must provide at least one of the following attributes: project_id or project_name")
    end

    project_name = resource[:project_name].strip.sub('/','%2F')

    url = "#{git_server}/api/v3/projects/#{project_name}"

    begin
      response = api_call('GET', url)
      return JSON.parse(response.body)['id'].to_i 
    rescue Exception => e
      fail(Puppet::Error, "git_deploy_key: #{e.message}")
      return nil
    end

  end

  def get_key_id
    project_id = get_project_id

    keys_hash = Hash.new

    url = "#{git_server}/api/v3/projects/#{project_id}/keys"

    response = api_call('GET', url)

    keys_json = JSON.parse(response.body)

    keys_json.each do |child|
      keys_hash[child['key']] = child['id']
    end

    keys_hash.each do |k,v|
      if k.eql?(File.read(resource[:path]).strip)
        return v.to_i
      end
    end

    return nil
  end
    
  def create
    project_id = get_project_id

    url = "#{git_server}/api/v3/projects/#{project_id}/keys"

    begin
      response = api_call('POST', url, {'title' => resource[:name].strip, 'key' => File.read(resource[:path].strip)})

      if (response.class == Net::HTTPCreated)
        return true
      else
        raise(Puppet::Error, "git_deploy_key: #{response.inspect}")
      end
    rescue Exception => e
      raise(Puppet::Error, e.message)
    end
  end

  def destroy
    project_id = get_project_id

    key_id = get_key_id

    unless key_id.nil?
      url = "#{git_server}/api/v3/projects/#{project_id}/keys/#{key_id}"

      begin
        response = api_call('DELETE', url)

        if (response.class == Net::HTTPOK)
          return true
        else
          raise(Puppet::Error, "git_deploy_key: #{response.inspect}")
        end
      rescue Exception => e
        raise(Puppet::Error, e.message)
      end

    end
  end

end


