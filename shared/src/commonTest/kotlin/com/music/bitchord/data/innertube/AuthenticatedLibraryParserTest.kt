package com.music.bitchord.data.innertube

import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Synthetic provider-shaped data. No account data or credentials. */
class AuthenticatedLibraryParserTest {
    @Test fun `duplicate and malformed cards preserve valid library items`() {
        val payload = Json.parseToJsonElement("""
          {"contents":[
            {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Private playlist"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"VLprivate"}}}},
            {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Duplicate"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"VLprivate"}}}},
            {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Invalid"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":""}}}},
            {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Album"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"MPREalbum"}}}},
            {"musicTwoRowItemRenderer":{"title":null,"navigationEndpoint":null}},
            null, 42
          ]}
        """.trimIndent())
        val cards = InnertubeParser.parseLibraryItems(payload)
        assertEquals(listOf("VLprivate", "MPREalbum"), cards.map { it.browseId })
        assertEquals(listOf("Private playlist", "Album"), cards.map { it.title })
    }

    @Test fun `empty or incomplete feeds are safe`() {
        assertTrue(InnertubeParser.parseLibraryItems(Json.parseToJsonElement("{}" )).isEmpty())
        assertTrue(InnertubeParser.parseLibraryItems(Json.parseToJsonElement("[null,42,{}]")).isEmpty())
    }
}
