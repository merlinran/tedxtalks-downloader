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
client_id = config['client_id']
db = {}
# db = YAML.load_file('videos.yml') if File.exists?('videos.yml')
begin
  if config['user_id'] then
    user_id = config['user_id']
    printf "fetching video records of user# %s...", user_id
    page = 1
    begin
      txt = RestClient.get('https://openapi.youku.com/v2/videos/by_user.json',
                           params: {client_id: client_id, user_id: user_id, page: page})
      result = JSON.parse(txt)
      fetchedCount = result["page"].to_i * result["count"]
      total = result["total"].to_i
      printf "fetched %d of %d records\n", fetchedCount, total
      result['videos'].each do |record|
        unless db[record['id']] and db[record['id']]["downloaded"]
          record.delete('user')
          db[record['id']] = record
        end
      end
      break if fetchedCount >= total
      page += 1
    end while true
  end

  if config['playlists'] then
    config['playlists'].each do |pl|
      result = RestClient.get('https://openapi.youku.com/v2/playlists/videos.json',
                              params: {client_id: config['client_id'],
                                       playlist_id: pl})
      db.update(videoArrayToHash(JSON.parse(result)['videos']))
    end
  end

  printf "downloading videos..."

rescue => e
  print e #.response
ensure
  since = config['since'] || Date.new(1970,1,1)
  till = config['till'] || Date.today
  db.delete_if do |id, record|
    published = Date.strptime(record['published'], '%Y-%m-%d')
    !(since <= published && published <= till)
  end

  File.open('videos.yml', 'w') do |f|
    YAML.dump(db, f)
  end

  File.open('links.txt', 'w') do |f|
    db.each do |id, record|
      f.print "you-get -F ", record["streamtypes"][0], " -o /Volumes/Backup/TEDxTalks ", record["link"]
      f.print "\t#", record["title"], " ", record["published"], "\n"
    end
  end
end
