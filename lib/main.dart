import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'dart:async';
import 'dart:math';

// Initialize Firebase before running the app
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase with platform-specific options

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MemoryGameApp());
}

/// Main application widget that sets up the theme and routes
class MemoryGameApp extends StatelessWidget {
  const MemoryGameApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Memory Game',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // Define app routes for navigation

      routes: {
        '/': (context) => const MemoryGameScreen(),
        '/leaderboard': (context) => const LeaderboardScreen(),
      },
    );
  }
}

// Service class to handle all Firebase interactions
// Manages authentication and Firestore operations for the game
class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign in anonymously to track scores
  Future<User?> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      return userCredential.user;
    } catch (e) {
      debugPrint('Error signing in: $e');
      return null;
    }
  }

  // Get current user
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Submit score to leaderboard
  // Also updates the user's personal best if the new score is higher
  Future<void> submitScore(int score, String playerName) async {
    try {
      // Get current user or sign in anonymously if no user exists
      // Will probably keep all users anonymous
      User? user = getCurrentUser();
      if (user == null) {
        user = await signInAnonymously();
      }

      if (user == null) return;

      // Use provided name or default to 'Anonymous Player'
      final playerNameToUse = playerName.isEmpty ? 'Anonymous Player' : playerName;

      // Add score to global leaderboard
      await _firestore.collection('leaderboard').add({
        'userId': user.uid,
        'playerName': playerNameToUse,
        'score': score,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update or create user's personal best
      final userScoreDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('scores')
          .doc('personal_best')
          .get();

      if (!userScoreDoc.exists || (userScoreDoc.data()?['score'] ?? 0) < score) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('scores')
            .doc('personal_best')
            .set({
          'score': score,
          'playerName': playerNameToUse,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error submitting score: $e');
    }
  }

  // Get top scores
  // Returns a list of maps containing player info and scores
  Future<List<Map<String, dynamic>>> getTopScores({int limit = 10}) async {
    try {
      // Query leaderboard collection for top scores
      final querySnapshot = await _firestore
          .collection('leaderboard')
          .orderBy('score', descending: true)
          .limit(limit)
          .get();

      // Convert query results to a list of maps
      return querySnapshot.docs
          .map((doc) => {
        'id': doc.id,
        'playerName': doc.data()['playerName'] ?? 'Anonymous',
        'score': doc.data()['score'] ?? 0,
        'timestamp': doc.data()['timestamp'] ?? Timestamp.now(),
      })
          .toList();
    } catch (e) {
      debugPrint('Error getting top scores: $e');
      return [];
    }
  }
}

// Game leaderboard screen
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({Key? key}) : super(key: key);

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _leaderboardEntries = [];

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  // Load leaderboard data from Firebase
  Future<void> _loadLeaderboard() async {
    setState(() {
      _isLoading = true;
    });

    final scores = await _firebaseService.getTopScores();

    setState(() {
      _leaderboardEntries = scores;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: [
          // Refresh button to reload leaderboard data
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLeaderboard,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _leaderboardEntries.isEmpty
          ? const Center(child: Text('No scores yet! Be the first to play!'))
          : ListView.builder(
        itemCount: _leaderboardEntries.length,
        itemBuilder: (context, index) {
          final entry = _leaderboardEntries[index];
          final rank = index + 1;

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: _getRankColor(rank),
              child: Text(
                rank.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              entry['playerName'],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Score: ${entry['score']}',
            ),
            trailing: entry['timestamp'] != null
                ? Text(
              _formatTimestamp(entry['timestamp']),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            )
                : null,
          );
        },
      ),
    );
  }

  // Returns a color based on the player's rank
  // Gold for 1st, Silver for 2nd, Bronze for 3rd, Blue for others
  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber; // Gold
      case 2:
        return Colors.blueGrey[300]!; // Silver
      case 3:
        return Colors.brown; // Bronze
      default:
        return Colors.blue;
    }
  }

  // Formats a Firestore timestamp into a readable date string
  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }
}

// Main game screen where the memory game is played
class MemoryGameScreen extends StatefulWidget {
  const MemoryGameScreen({Key? key}) : super(key: key);

  @override
  State<MemoryGameScreen> createState() => _MemoryGameScreenState();
}

class _MemoryGameScreenState extends State<MemoryGameScreen> {
  final random = Random();
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _nameController = TextEditingController();

  // Game state variables
  List<int> sequence = [];       // The sequence of buttons to remember
  List<int> playerSequence = []; // The sequence input by the player
  int level = 1;                 // Current game level
  bool isPlaying = false;        // Whether a game is in progress
  bool isShowingSequence = false; // Whether the game is showing the sequence
  bool gameOver = false;         // Whether the game is over
  int score = 0;                 // Current game score
  int highScore = 0;             // Highest score achieved in this session
  String playerName = '';        // Player's name for leaderboard
  bool scoreSaved = false;       // Whether the score has been saved

  // Colors for the buttons
  final List<Color> buttonColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.teal,
    Colors.indigo,
  ];

  // Active button highlight color
  final Color activeColor = Colors.white;

  @override
  void initState() {
    super.initState();
    // Try to sign in anonymously when app starts
    _firebaseService.signInAnonymously();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Starts a new game and resets all game variables
  void startGame() {
    setState(() {
      sequence = [];
      playerSequence = [];
      level = 1;
      score = 0;
      gameOver = false;
      isPlaying = true;
      scoreSaved = false;
    });

    addToSequence();
  }

  // Add the button to the sequence
  void addToSequence() {
    setState(() {
      isShowingSequence = true;
      // Add a random button (0-8) to the sequence
      sequence.add(random.nextInt(9));
      playerSequence = [];
    });

    // Show the sequence to the player
    playSequence();
  }

  // Plays the current sequence for the player to observe
  void playSequence() async {
    // Wait before starting the sequence
    await Future.delayed(const Duration(milliseconds: 500));

    // Play each button in the sequence
    for (int i = 0; i < sequence.length; i++) {
      if (!isPlaying) return; // Stop if game ended

      final buttonIndex = sequence[i];

      // Light up the button
      setState(() {
        highlightButton = buttonIndex;
      });

      // Wait while the button is highlighted
      await Future.delayed(const Duration(milliseconds: 600));

      // Turn off the highlight
      setState(() {
        highlightButton = -1;
      });

      // Pause between buttons
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // Sequence finished, player's turn
    setState(() {
      isShowingSequence = false;
    });
  }

  int highlightButton = -1;

  // Handles when a player presses a button
  void onButtonPressed(int index) {
    // Ignore button presses if not in the player's turn
    if (!isPlaying || isShowingSequence || gameOver) return;

    setState(() {
      playerSequence.add(index);
      highlightButton = index;
    });

    // Check if the player's sequence matches so far
    final currentIndex = playerSequence.length - 1;
    if (playerSequence[currentIndex] != sequence[currentIndex]) {
      // Wrong button - game over
      endGame();
      return;
    }

    // Turn off highlight after a short delay
    Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          highlightButton = -1;
        });
      }
    });

    // Check if player completed the current sequence
    if (playerSequence.length == sequence.length) {
      // Completed current level
      setState(() {
        level++;
        score += sequence.length * 10; // Score increases with sequence length
      });

      // Add new button to sequence after delay
      Timer(const Duration(milliseconds: 1000), () {
        if (mounted && isPlaying) {
          addToSequence();
        }
      });
    }
  }

  void endGame() {
    setState(() {
      gameOver = true;
      isPlaying = false;
      if (score > highScore) {
        highScore = score;
      }
    });

    // Show game over animation
    highlightButton = sequence[playerSequence.length - 1];

    // Flash the correct button 3 times
    Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          highlightButton = -1;
        });

        Timer(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              highlightButton = sequence[playerSequence.length - 1];
            });

            Timer(const Duration(milliseconds: 300), () {
              if (mounted) {
                setState(() {
                  highlightButton = -1;
                });

                // Show dialog to save score if it's worth saving (more than 50 points)
                if (score > 50 && !scoreSaved) {
                  _showSaveScoreDialog();
                }
              }
            });
          }
        });
      }
    });
  }

  // Show a dialog to save the player's score to the leaderboard
  void _showSaveScoreDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Great Job!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Your score: $score'),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Enter your name',
                  border: OutlineInputBorder(),
                ),
                maxLength: 20,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () async {
                playerName = _nameController.text.trim();
                await _firebaseService.submitScore(score, playerName);
                setState(() {
                  scoreSaved = true;
                });
                Navigator.of(context).pop();
              },
              child: const Text('Save Score'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Game'),
        centerTitle: true,
        actions: [
          // Button to navigate to the leaderboard screen
          IconButton(
            icon: const Icon(Icons.leaderboard),
            onPressed: () {
              Navigator.pushNamed(context, '/leaderboard');
            },
            tooltip: 'Leaderboard',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Game stats display (level, score, high score)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildInfoCard('Level', level.toString()),
                _buildInfoCard('Score', score.toString()),
                _buildInfoCard('High Score', highScore.toString()),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 3x3 game grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: 9,
                itemBuilder: (context, index) {
                  final isHighlighted = highlightButton == index;
                  return GestureDetector(
                    onTap: () => onButtonPressed(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isHighlighted ? activeColor : buttonColors[index],
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            offset: const Offset(0, 4),
                            blurRadius: 5.0,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Play button
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                textStyle: const TextStyle(fontSize: 20),
              ),
              onPressed: isPlaying ? null : startGame,
              child: Text(gameOver ? 'Play Again' : (isPlaying ? 'Playing...' : 'Start Game')),
            ),
          ),
          // Game over messages
          if (gameOver)
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Text(
                'Game Over! Your score: $score',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          if (isShowingSequence)
            const Padding(
              padding: EdgeInsets.only(bottom: 24.0),
              child: Text(
                'Watch carefully!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          if (isPlaying && !isShowingSequence && !gameOver)
            const Padding(
              padding: EdgeInsets.only(bottom: 24.0),
              child: Text(
                'Your turn! Repeat the sequence',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  // Helper method to build info cards for displaying game stats
  Widget _buildInfoCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }
}