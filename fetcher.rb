#! /usr/bin/env ruby
require 'json'
require 'yaml'
require 'yaml/dbm'
require 'rest-client'

def videoArrayToHash(array)
  return array.inject({}) do |r, v|
    r.merge!({v['id'] => v})
  end
end
config = YAML.load_file('config.yml')
db = {}
db = YAML.load_file('videos.yml') if File.exists?('videos.yml')
begin
  if config['user_id'] then
    result = RestClient.get('https://openapi.youku.com/v2/videos/by_user.json',
                            params: {client_id: config['client_id'],
                                     user_id: config['user_id']})
    db.update(videoArrayToHash(JSON.parse(result)['videos']))
  end

  if config['playlists'] then
    config['playlists'].each do |pl|
      result = RestClient.get('https://openapi.youku.com/v2/playlists/videos.json',
                              params: {client_id: config['client_id'],
                                       playlist_id: pl})
      db.update(videoArrayToHash(JSON.parse(result)['videos']))
    end
  end

rescue => e
  print e #.response
ensure
  File.open('videos.yml', 'w') do |f|
    YAML.dump(db, f)
  end
end
