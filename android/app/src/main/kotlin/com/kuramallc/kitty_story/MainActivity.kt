package com.kuramallc.kitty_story

import com.ryanheise.audioservice.AudioServiceActivity

// Extends AudioServiceActivity so audio_service can keep narration playing in
// the background and show lock-screen / media controls.
class MainActivity : AudioServiceActivity()
