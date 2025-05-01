# Sequence Memeory Game
Simple memory game where the player has to remember the sequence of tiles to click on a 3x3 grid.

## Getting Started
google-services.json (android/app and android/app/src) and firebase_options.dart were omitted from repo.
* google-services.json can be obtained from Firebase studio.
* firebase_options.dart can be obtained from installed [Firebase CLI](https://firebase.google.com/docs/cli) and running the "flutterfire configure" command.

## How To Play
* Players can press start to play
* Tiles will be highlighted and increase in amount each round
* Players need to remember and press on the tiles in sequential order to progress
 * Tiles can not be pressed during display phase
* Game stops when the player clicks a wrong tile
* If the the player scores above 50 points, their name can be added to the leaderboard

### Leaderboard
The leaderboard can be accessed by pressed the icon in the top-corner corner of the screen.
* The top 10 scores will be display on leaderboard
* There is a refresh leaderboard button in the top-right corner
