import Foundation

func data(_ text: String) -> Data { Data(text.utf8) }
let valid = data("""
{"auth_url":"https://cdn.example.test/audio.mp4?token=abc"}
""")
precondition(JioSaavnResponse.streamURL(data: valid, statusCode: 200)?.host == "cdn.example.test")
precondition(JioSaavnResponse.streamURL(data: valid, statusCode: 403) == nil)
precondition(JioSaavnResponse.streamURL(data: data("not json"), statusCode: 200) == nil)
precondition(JioSaavnResponse.streamURL(data: data("{\"auth_url\":\"http://example.test/a\"}"), statusCode: 200) == nil)
precondition(JioSaavnResponse.streamURL(data: data("{\"auth_url\":\"https://user:pass@example.test/a\"}"), statusCode: 200) == nil)
precondition(JioSaavnResponse.streamURL(data: data("{}"), statusCode: 200) == nil)
print("JioSaavn response validation passed")
