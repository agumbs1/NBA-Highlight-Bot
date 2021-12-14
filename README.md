# Nba Highlight Bot
Selenium/HTTP Request based NBA highlight compiler and editor made with Ruby

- uses HTTP requests to compile a list of all players in the NBA who scored 30 or more points that day from nba.com 
- for each player:
  - uses Selenium based Ruby plugin Watir to navigate through the NBA play-by-play website and access the mp4 files of the clip each time the player scored
  - downloads each clip and uses open-source command line software FFmpeg to stitch together each clip and create a highlight tape
  - uses Twitter API to tweet each clip with a caption
 
