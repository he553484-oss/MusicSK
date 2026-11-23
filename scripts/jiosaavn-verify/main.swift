import Foundation

func data(_ text: String) -> Data { Data(text.utf8) }
precondition(JioSaavnResponse.durationSeconds(123.6) == 124)
precondition(JioSaavnResponse.durationSeconds(.infinity) == nil)
precondition(JioSaavnResponse.durationSeconds(.nan) == nil)
precondition(JioSaavnResponse.durationSeconds(Double(Int32.max) + 1) == nil)
precondition(JioSaavnResponse.durationSeconds(-1) == nil)
let valid = data("""
{"auth_url":"https://cdn.example.test/audio.mp4?token=abc"}
""")
precondition(JioSaavnResponse.streamURL(data: valid, statusCode: 200)?.host == "cdn.example.test")
precondition(JioSaavnResponse.streamURL(data: valid, statusCode: 403) == nil)
precondition(JioSaavnResponse.streamURL(data: data("not json"), statusCode: 200) == nil)
precondition(JioSaavnResponse.streamURL(data: data("{\"auth_url\":\"http://example.test/a\"}"), statusCode: 200) == nil)
precondition(JioSaavnResponse.streamURL(data: data("{\"auth_url\":\"https://user:pass@example.test/a\"}"), statusCode: 200) == nil)
precondition(JioSaavnResponse.streamURL(data: data("{}"), statusCode: 200) == nil)
precondition(JioSaavnResponse.streamURL(data: data("{\"status\":\"error\",\"auth_url\":\"https://example.test/a\"}"), statusCode: 200) == nil)
let rows = #"{"results":[null,{"id":"track","title":"Song"},{"id":" ","title":"Bad"},{"id":"other","title":" "},42]}"#
precondition(JioSaavnResponse.searchRows(data: data(rows)).count == 1)
precondition(JioSaavnResponse.searchRows(data: data(#"[{"id":"track","title":"Song"}]"#)).count == 1)
precondition(JioSaavnResponse.searchRows(data: data(#"{"data":[{"id":"track","title":"Song"}]}"#)).count == 1)
precondition(JioSaavnResponse.searchRows(data: data("broken")).isEmpty)
let songs: [String: Any] = ["songs": [["id": "other"], ["id": "wanted"]]]
precondition(JioSaavnResponse.song(in: songs, id: "wanted")?["id"] as? String == "wanted")
let mixed: [String: Any] = ["songs": [NSNull(), ["id": "wanted"], 42]]
precondition(JioSaavnResponse.song(in: mixed, id: "wanted")?["id"] as? String == "wanted")
precondition(JioSaavnResponse.song(in: songs, id: "missing") == nil)
precondition(JioSaavnResponse.song(in: ["other": ["id": "other"]], id: "wanted") == nil)
precondition(JioSaavnResponse.song(in: ["wanted": ["id": "other"]], id: "wanted") == nil)
precondition(JioSaavnResponse.song(in: ["wanted": ["id": "wanted"]], id: "wanted") != nil)
print("JioSaavn response validation passed")
