package com.music.bitchord.data.sources

import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.CancellationException
import kotlin.test.*

class JioSaavnTransportTest {
    @Test fun cancellationIsNotConvertedIntoAnUnavailableSong() = runTest {
        val source = JioSaavnSource(SourceConfig(kind = SourceKind.JIOSAAVN)) { _, _ ->
            throw CancellationException("cancelled fixture")
        }
        var cancelled = false
        try {
            source.stream("fixture", StreamRequest.Best)
        } catch (_: CancellationException) {
            cancelled = true
        }
        assertTrue(cancelled)
    }

    @Test fun fallsBackWhenRequestedRenditionHasNoUrl() = runTest {
        val requested = mutableListOf<String>()
        val source = JioSaavnSource(SourceConfig(kind = SourceKind.JIOSAAVN)) { call, args ->
            when (call) {
                "song.getDetails" -> """{"songs":[{"id":"fixture","title":"Example","more_info":{"encrypted_media_url":"opaque"}}]}"""
                "song.generateAuthToken" -> {
                    val bitrate = args["bitrate"].orEmpty()
                    requested += bitrate
                    if (bitrate == "160") """{"auth_url":"https://example.test/audio.mp4"}""" else """{}"""
                }
                else -> error("Unexpected API method")
            }
        }
        val stream = source.stream("fixture", StreamRequest.Best)
        assertNotNull(stream)
        assertEquals(listOf("320", "160"), requested)
        assertEquals("https://example.test/audio.mp4", stream.url)
        assertNull(stream.format.kbps)
        assertNull(stream.format.codec)
    }

    @Test fun catalogueAndMediaUseProviderProtocol() = runTest {
        val calls = mutableListOf<String>()
        val song = """{"id":"fixture","title":"Example","image":"https://example.test/150x150.jpg","explicit_content":"1","more_info":{"album":"Album","duration":"180","encrypted_media_url":"opaque","artistMap":{"primary_artists":[{"name":"Artist"}]}}}"""
        val source = JioSaavnSource(SourceConfig(kind = SourceKind.JIOSAAVN)) { call, args ->
            calls += call
            when (call) {
                "search.getResults" -> { assertEquals("Example", args["q"]); """{"results":[$song]}""" }
                "song.getDetails" -> { assertEquals("fixture", args["pids"]); """{"songs":[$song]}""" }
                "song.generateAuthToken" -> {
                    assertEquals("opaque", args["url"])
                    assertEquals("320", args["bitrate"])
                    """{"auth_url":"https://example.test/audio.mp4","status":"success"}"""
                }
                else -> error("Unexpected API method")
            }
        }
        val rows = source.search("Example", 5, false, null)
        assertEquals("Example", rows.single().title)
        assertEquals("Artist", rows.single().artist)
        val stream = source.stream("fixture", StreamRequest.Best)
        assertNotNull(stream)
        assertEquals("https://example.test/audio.mp4", stream.url)
        assertNull(stream.format.kbps)
        assertNull(stream.format.codec)
        assertEquals(180, stream.durationSec)
        assertFalse(stream.format.isLossless == true)
        assertEquals(listOf("search.getResults", "song.getDetails", "song.generateAuthToken"), calls)
    }
}
