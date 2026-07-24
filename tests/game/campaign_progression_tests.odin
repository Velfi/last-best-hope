package game_tests

import "core:testing"

@(test)
story_tempo_controls_major_beat_spacing :: proc(t: ^testing.T) {
	measured: Campaign
	campaign_init(&measured, 1)
	measured.last_major_beat_season = 0
	measured.season = 1
	testing.expect(t, !major_story_beat_ready(&measured))
	measured.season = 2
	testing.expect(t, major_story_beat_ready(&measured))

	spacious: Campaign
	campaign_init(&spacious, 1)
	spacious.story_tempo = .Spacious
	spacious.last_major_beat_season = 0
	spacious.season = 2
	testing.expect(t, !major_story_beat_ready(&spacious))
	spacious.season = 3
	testing.expect(t, major_story_beat_ready(&spacious))

	volatile: Campaign
	campaign_init(&volatile, 1)
	volatile.story_tempo = .Volatile
	volatile.last_major_beat_season = 0
	volatile.season = 1
	testing.expect(t, major_story_beat_ready(&volatile))
}
