package gemini

import "testing"

// API traffic must stay out of the account's history by default, but saved-chat features and opted-in
// history (GEMINI_SAVE_HISTORY=true) need a regular conversation.
func TestUseTemporaryChat(t *testing.T) {
	cases := []struct {
		name        string
		guest       bool
		saveHistory bool
		feature     Feature
		want        bool
	}{
		{"plain chat uses temporary chat", false, false, 0, true},
		{"image generation uses temporary chat", false, false, FeatureImage, true},
		{"saveHistory opts in to saved chats", false, true, 0, false},
		{"guest has no history to hide", true, false, 0, false},
		{"task needs a regular chat", false, false, FeatureTask, false},
		{"deep research needs a regular chat", false, false, FeatureDeepResearch, false},
		{"video reads its result from the conversation", false, false, FeatureVideo, false},
	}
	for _, tc := range cases {
		if got := useTemporaryChat(tc.guest, tc.saveHistory, tc.feature); got != tc.want {
			t.Errorf("%s: got %v, want %v", tc.name, got, tc.want)
		}
	}
}
