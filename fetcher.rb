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

def get_page(user_id, page, since)
  uri = URI("http://i.youku.com/u/#{user_id}/videos")
  params = { order: 1, page: page }
  uri.query = URI.encode_www_form(params)
  res = Net::HTTP.get_response(uri)
  if not res.is_a?(Net::HTTPSuccess) then
    return []
  end
  result = []
  res.body.scan(/<div class="v-meta">.*?<\/div>\s*<\/div>\s*<\/div>/) do |m|
    link = m.scan(/<a href="(.*?)"/)[0]
    if link.nil?
      next
    end
    link = "http:"+link[0]
    title = m.scan(/title="(.*?)"/)[0][0]
    publish_time = m.scan(/<span class="v-publishtime">(.*?)<\/span>/)[0][0]
    publish_time.scan(/(\d\d-\d\d) [\d:]+/) do |m|
      publish_time = "#{Date.today().year}-#{m[0]}"
    end
    publish_time.force_encoding('utf-8').scan(/(\d)天前/u) do |m|
      publish_time = (Date.today() - m[0].to_i).to_s
    end
    if since.to_s > publish_time
      break
    end
    result = result.push({title: title, link: link, publish_date: publish_time})
  end
  printf "%d results on page %d\n", result.length, page
  return result
end

def fetch()
  db = []
  config = YAML.load_file('config.yml')
  client_id = config['client_id']
  since = config['since'] || Date.new(1970,1,1)
  till = config['till'] || Date.today
  begin
    if config['user_id'] then
      user_id = config['user_id']
      printf "fetching video records of user# %s...\n", user_id
      oldest = Date.today
      page = 1
      begin
        res = get_page(user_id, page, since)
        db = db.concat(res)
        page += 1
      end while res.length > 0
    end
  end
  printf "%d videos pending download since %s\n", db.length, since
  return db
end

def exec(fmt, *params)
  cmd = sprintf(fmt, *params)
  print "> ", cmd
  system(cmd)
end

root="~/Downloads/TEDxTalks/"
format_ext = {
  "3gphd" => "3gp",
  "flvhd" => "flv",
  "mp4" => "mp4",
  "hd2" => "mp4",
  "hd3" => "mp4",
}

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

db.each do |record|
  matched = /TE[DX]x([A-z'@0-9]+)/.match(record[:title])
  publish_month = record[:publish_date][0, 7]
  event = matched ? publish_month + "-" + matched[1].sub("'", "") : publish_month
  title = record[:title].gsub(/["':\\\/]/, "")
  opath = File.expand_path(File.join(root, event))
  exec "mkdir -p '%s'\n", opath
  mp3_full_path = File.join(opath, title) + ".mp3"
  if File.exist?(mp3_full_path) then
    printf "Skipping already downloaded talk '%s'\n", title
    next
  end
  begin
    video_path = ''
    for format, ext in format_ext
      begin
        video_path = "#{title}.#{ext}"
        exec "you-get -F %s -O '%s' %s\n", format, title, record[:link]
      rescue
        next
      end
      if File.exist?(video_path) then
        break
      end
    end
    print "converting to mp3...\n"
    exec "ffmpeg -loglevel error -y -i '%s' '%s.mp3'\n", video_path, title
    exec "ffmpeg -loglevel error -y -i '%s.mp3' -metadata album='%s' '%s'\n", title, event, mp3_full_path
  ensure
    exec "rm -f '%s' '%s.mp3'\n\n", video_path, title
  end
end
