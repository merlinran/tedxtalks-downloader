#! /usr/bin/env ruby

require 'json'
require 'yaml'
require 'yaml/dbm'
require 'optparse'
require 'rest-client'

def videoArrayToHash(array)
  return array.inject({}) do |r, v|
    r.merge!({v['id'] => v})
  end
end

def fetch()
  db = {}
  # db = YAML.load_file('videos.yml') if File.exists?('videos.yml')
  #
  config = YAML.load_file('config.yml')
  client_id = config['client_id']
  since = config['since'] || Date.new(1970,1,1)
  till = config['till'] || Date.today
  begin
    if config['user_id'] then
      user_id = config['user_id']
      printf "fetching video records of user# %s...\n", user_id
      fetchedCount = 0
      last_item = nil
      oldest = Date.today
      page = 1
      begin
        txt = RestClient.get('https://openapi.youku.com/v2/videos/by_user.json',
                             params: {client_id: client_id, user_id: user_id, last_item: last_item, page: page, orderby: "published"})
                             # params: {client_id: client_id, user_id: user_id, last_item: last_item, page: page, count: 100, orderby: "published"})
        result = JSON.parse(txt)
        total = result["total"].to_i
        fetchedCount += result['videos'].length
        printf "fetched %d of %d records\n", fetchedCount, total
        result['videos'].each do |record|
          if record["state"] == "normal" and record["public_type"] == "all" then
            record.delete('user')
            record["publish-date"] = Date.strptime(record['published'], '%F %T')
            if oldest > record["publish-date"] then
              oldest = record["publish-date"]
            end
            db[record['id']] = record
          end
        end
        if oldest < since then
          printf "stop fetching talks older than %s\n", since
          break
        end
        page += 1
        last_item = result["last_item"]
      end while fetchedCount < total
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
    print e.response
  ensure
    db.delete_if do |id, record|
      published = record["publish-date"]
      !(since <= published && published <= till)
    end
  end

  return db
end

def exec(fmt, *params)
  cmd = sprintf(fmt, *params)
  print "> ", cmd
  system(cmd)
end

root="~/Downloads/TEDxTalks/"
format_order = {
  "3gphd" => 9999,
  "flvhd" => 1,
  "mp4" => 2,
  "hd2" => 3,
  "hd3" => 4,
}
format_order.default = 9999

OptionParser.new do |opts|
  opts.banner = "Usage: fetcher.rb [-o dir]"
  opts.on("-oDIR", "--output-dir=DIR", "The output dir of audio files") do |v|
    root = v
  end
end.parse!

db = fetch()
File.open('videos.yml', 'w') do |f|
  YAML.dump(db, f)
end

db.each do |id, record|
  matched = /TE[DX]x([A-z'@0-9]+)/.match(record["title"])
  publish_month = record["published"][0, 7]
  event = matched ? publish_month + "-" + matched[1].sub("'", "") : publish_month
  format = record["streamtypes"].sort do |a, b|
    format_order[a] - format_order[b]
  end[0]
  title = record["title"].gsub(/["':\\\/]/, "")
  opath = File.expand_path(File.join(root, event))
  exec "mkdir -p '%s'\n", opath
  target_desc = File.join(opath, title) + ".txt"
  File.open(target_desc, 'w') do |f|
    f.print record["desc"]
  end

  target = File.join(opath, title) + ".mp3"
  if File.exist?(target) then
    printf "Skipping already downloaded talk '%s'\n", title
    next
  end
  begin
    exec "you-get -F %s -O '%s.mp4' %s\n", format, title, record["link"]
    print "converting to mp3...\n"
    exec "ffmpeg -loglevel error -y -i '%s.mp4' '%s.mp3'\n", title, title
    exec "ffmpeg -loglevel error -y -i '%s.mp3' -metadata album='%s' '%s'\n", title, event, target
  ensure
    exec "rm '%s.mp4' '%s.mp3'\n\n", title, title
  end
end
