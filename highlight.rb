require 'twitter'
require 'json'
require 'watir'
require 'watir-scroll'
require 'webdrivers'
require 'down'
require 'fileutils'
require 'rest-client'


def get_hoopers
    res = RestClient.get("https://cdn.nba.com/static/json/liveData/scoreboard/todaysScoreboard_00.json")
    File.open("out.json", "w") {|f| f.write( res.body ) }

    json = JSON.parse( res.body )
#    json = JSON.parse( File.read( "out.json" ) )

    game_count = json["scoreboard"]["games"].size
    games = json["scoreboard"]["games"]
    
    hoopers_hash = {}
    i = 0

    until i == game_count        
        home_points = games[i]["gameLeaders"]["homeLeaders"]["points"].to_i
        away_points = games[i]["gameLeaders"]["awayLeaders"]["points"].to_i
        
        home_scorers = games[i]["gameLeaders"]["homeLeaders"]["name"]
        away_scorers = games[i]["gameLeaders"]["awayLeaders"]["name"]
        
        game_id = games[i]["gameId"]
        home_tri = games[i]["homeTeam"]["teamTricode"]
        away_tri = games[i]["awayTeam"]["teamTricode"]
        link = "https://www.nba.com/game/#{away_tri}-vs-#{home_tri}-#{game_id}/play-by-play"
        
        
        if home_points >= 30
            vs = games[i]["awayTeam"]["teamCity"] + " " + games[i]["awayTeam"]["teamName"]
            
            hoopers_hash[home_scorers] = {
                "link" => link,
                "points" => home_points,
                "vs" => vs
            }
        end
        
        if away_points >= 30
            vs = games[i]["homeTeam"]["teamCity"] + " " + games[i]["homeTeam"]["teamName"]
            
            hoopers_hash[away_scorers] = {
                "link" => link,
                "points" => away_points,
                "vs" => vs
            }
        end

        i += 1
    end

    return hoopers_hash
end

def check_hoopers(pre_hash)
    hash = pre_hash
    players = hash.keys
    players.map{ |i|
        points = hash[i]["points"]
        puts "\nmake video for #{i} (#{points})? (press 1 for yes)"
        conf = gets.chomp

        if conf != "1"
            puts "#{i} will not be included"
            hash.delete(i)
        end
    }

    return hash
end

def get_playlist(player, info_hash)
    link = info_hash[player]["link"]

    @browser = Watir::Browser.new
    @browser.goto( link )

    @browser.a(text: "Play-By-Play").scroll.to
    @browser.button(text: "ALL").click

    playlist = @browser.element(:xpath => '//*[@id="__next"]/div[2]/div[4]/section/div/div[4]').text
#    File.open("out.txt", "w") {|f| f.write( playlist ) }
    
    return playlist
end

def sort_plays(player, playlist)    
    first_name = player.split(" ")[0]
    last_name = player.split(" ")[1] 
    
    array = playlist.split("\n")
    
    scoring_plays = []
        
    array.map { |i|
        if (i.include? last_name) && (i.split(" ")[0] == last_name) && (i.include? "PTS") && (i.include? "'")
             scoring_plays.append(i)
        end
    }
    
    return scoring_plays
end


def get_links(player, scoring_plays, info_hash)
    pbp_link = info_hash[player]["link"]
    sources = []

    scoring_plays.map { |i|
        vid_link = @browser.a(text: i).href
        @browser.goto( vid_link )      

        vid = @browser.video(id: "stats-videojs-player_html5_api").src
        sources.append( vid )
        
        @browser.goto( pbp_link )

        @browser.a(text: "Play-By-Play").scroll.to
        @browser.button(text: "ALL").click
    }

    @browser.close
#    File.open("sources.txt", "w") {|f| f.puts( sources ) }
    return sources
end

def download_clips(sources)
    clips = []
    sources.map{ |n, i|
        begin
            temp = Down.download(n).path
            clips.append( temp )
        rescue
            puts "download error (#{i})"
            retry
        end
    }
    
    return clips
end

def stitch_clips(player, clips)
    last_name = player.split(" ")[1]
    temp_path = 'C:\sites\flutter\temp'
    alph = ("a".."z").to_a

    clips.map.with_index{ |x, i|
        
        `ffmpeg -i #{x} -c copy -bsf:v h264_mp4toannexb -f mpegts #{last_name}#{alph[i]}.ts`
        begin
            FileUtils.mv("#{last_name}#{alph[i]}.ts", temp_path)
        rescue
        end
    }


    temps = Dir.entries(temp_path).sort

    concat_group = ""

    i = 2
    until i == temps.count - 1
        file_name = temp_path + "\\" + temps[i]
        addition = '"' + file_name + '"' + "|"
        concat_group += addition 

        i += 1
    end

    file_name = temp_path + "\\" + temps[i]
    final_addition = '"' + file_name + '"'

    concat_group += final_addition

    `ffmpeg -i "concat:#{concat_group}" -c copy -bsf:a aac_adtstoasc #{last_name}.mp4`

    return temps
end

def clean_up
    temps = Dir.entries('C:\sites\flutter\temp')

    i = 2
    until i == temps.count
        path = ('C:\sites\flutter\temp\\')
        File.delete( path + temps[i] )

        i += 1
    end
end


def tweet_video(player, info_hash)    
    last_name = player.split(" ")[1]
    points = info_hash[player]["points"]
    vs = info_hash[player]["vs"]

    video = File.open( "#{last_name}.mp4" )
    
    json = JSON.parse(File.read( "config.json" ))

    key = json["api key"]
    secret_key = json["secret key"]
    token = json["access token"]
    secret_token = json["secret token"]


    client = Twitter::REST::Client.new do |config|
        config.consumer_key        = key
        config.consumer_secret     = secret_key
        config.access_token        = token
        config.access_token_secret = secret_token
    end

    msg = "all of #{player}'s #{points} points vs the #{vs}! #NBAALLSTAR"

    client.update_with_media(msg, video)
end

pre_hash = get_hoopers
info_hash = check_hoopers(pre_hash)

players = info_hash.keys
players.map{ |i|
    begin
        playlist = get_playlist(i, info_hash)
        scoring_plays = sort_plays(i, playlist)

        sources = get_links(i, scoring_plays, info_hash)
        clips = download_clips(sources)
        stitch_clips(i, clips)
        clean_up


        tweet_video(i, info_hash)

        puts "{#{i}: success}"
    rescue
        puts "{#{i}: failed}"
    end
}
