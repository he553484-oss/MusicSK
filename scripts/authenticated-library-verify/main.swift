import Foundation

func decode(_ text: String) throws -> [LibraryFeedDecoder.Shelf] {
    try LibraryFeedDecoder.decode(Data(text.utf8))
}

let input = #"""
{"shelves":[
 {"title":"Playlists","items":[
  {"title":"Privada","browseId":"VLprivate","subtitle":"Owner"},
  {"title":"Duplicada","browseId":"VLprivate"},
  {"title":"Sin ID","browseId":""}, null, 17,
  {"title":42,"browseId":"VLbad"},
  {"title":"Álbum","browseId":"MPREgood","thumbnailUrl":null}]},
 {"title":"Playlists","items":[{"title":"Otra","browseId":"VLother"}]},
 {"title":null,"items":[]},
 {"title":"Artists","items":null}
]}
"""#
let shelves = try decode(input)
precondition(LibraryFeedDecoder.belongsToCurrentSession(4, current: 4))
precondition(!LibraryFeedDecoder.belongsToCurrentSession(4, current: 5))
precondition(!LibraryFeedDecoder.belongsToCurrentSession(nil, current: 5))
precondition(shelves.count == 1)
precondition(shelves[0].title == "Playlists")
precondition(shelves[0].items.map(\.title) == ["Privada", "Álbum", "Otra"])
let empty = try decode(#"{"shelves":[]}"#)
precondition(empty.isEmpty)
do { _ = try decode(#"{"shelves":42}"#); fatalError("invalid response accepted") } catch {}
let items = (0..<10_000).map { ["title": "Track \($0)", "browseId": "VL\($0)"] }
let data = try JSONSerialization.data(withJSONObject: ["shelves": [["title":"Playlists", "items":items]]])
let large = try LibraryFeedDecoder.decode(data)
precondition(large[0].items.count == 10_000)
print("PASS authenticated library: incomplete records, duplicates, empty and 10,000 entries")
