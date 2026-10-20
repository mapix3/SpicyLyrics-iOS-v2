#include "SLScrollsita.h"
#include <stdlib.h>
#include <string.h>

// id секции текста в ответах scrollsita (одинаковый для всех треков)
static const char *const SLLyricsSectionID = "spotify:section:0JQ5DB6s3cssW5Bo6cGq21";

enum { SLStructureField = 1, SLSectionField = 1, SLLyricsField = 5, SLInfoField = 23 };

static int SLVarint(const uint8_t *p, size_t len, size_t *i, uint64_t *v) {
    uint64_t r = 0;
    for (int shift = 0; shift < 64; shift += 7) {
        if (*i >= len) return 0;
        uint8_t b = p[(*i)++];
        r |= (uint64_t)(b & 0x7F) << shift;
        if (!(b & 0x80)) { *v = r; return 1; }
    }
    return 0;
}

/// Следующее поле: номер, тип, для LEN — начало и длина значения; *i — за полем.
static int SLField(const uint8_t *p, size_t len, size_t *i, uint32_t *field, uint32_t *wire, size_t *vStart, size_t *vLen) {
    uint64_t key, v;
    if (!SLVarint(p, len, i, &key)) return 0;
    *field = (uint32_t)(key >> 3);
    *wire = (uint32_t)(key & 7);
    switch (*wire) {
        case 0: return SLVarint(p, len, i, &v);
        case 1: if (len - *i < 8) return 0; *i += 8; return 1;
        case 5: if (len - *i < 4) return 0; *i += 4; return 1;
        case 2:
            if (!SLVarint(p, len, i, &v) || v > len - *i) return 0;
            *vStart = *i; *vLen = (size_t)v; *i += (size_t)v;
            return 1;
        default: return 0;
    }
}

/// Проверяет, что весь буфер — корректный protobuf.
static int SLValid(const uint8_t *p, size_t len) {
    size_t i = 0, s, l; uint32_t f, w;
    while (i < len) if (!SLField(p, len, &i, &f, &w, &s, &l)) return 0;
    return 1;
}

typedef struct { uint8_t *p; size_t len, cap; int ok; } SLBuf;

static void SLPut(SLBuf *b, const void *data, size_t n) {
    if (!b->ok || !n) return;
    if (b->len + n > b->cap) {
        size_t cap = (b->cap ? b->cap * 2 : 256);
        while (cap < b->len + n) cap *= 2;
        uint8_t *np = realloc(b->p, cap);
        if (!np) { b->ok = 0; return; }
        b->p = np; b->cap = cap;
    }
    memcpy(b->p + b->len, data, n);
    b->len += n;
}

static void SLPutVarint(SLBuf *b, uint64_t v) {
    uint8_t tmp[10]; int n = 0;
    do { uint8_t c = v & 0x7F; v >>= 7; if (v) c |= 0x80; tmp[n++] = c; } while (v);
    SLPut(b, tmp, n);
}

static void SLPutLen(SLBuf *b, uint32_t field, const void *data, size_t n) {
    SLPutVarint(b, ((uint64_t)field << 3) | 2);
    SLPutVarint(b, n);
    SLPut(b, data, n);
}

uint8_t *SLScrollsitaAddLyrics(const uint8_t *in, size_t inLen, const char *trackURI, size_t *outLen) {
    if (!in || !inLen || !trackURI || !SLValid(in, inLen)) return NULL;

    // ищем structure(1)
    size_t i = 0, s, l, structStart = 0, structLen = 0, structFieldStart = 0, structFieldEnd = 0;
    uint32_t f, w;
    int found = 0;
    while (i < inLen) {
        size_t fieldStart = i;
        if (!SLField(in, inLen, &i, &f, &w, &s, &l)) return NULL;
        if (f == SLStructureField && w == 2 && !found) {
            found = 1; structStart = s; structLen = l; structFieldStart = fieldStart; structFieldEnd = i;
        }
    }
    if (!found || !SLValid(in + structStart, structLen)) return NULL;

    // секции: если среди них уже есть текст — ничего не делаем
    const uint8_t *st = in + structStart;
    int sections = 0;
    i = 0;
    while (i < structLen) {
        if (!SLField(st, structLen, &i, &f, &w, &s, &l)) return NULL;
        if (f != SLSectionField || w != 2) continue;
        sections++;
        const uint8_t *sec = st + s;
        size_t j = 0, s2, l2; uint32_t f2, w2;
        if (!SLValid(sec, l)) return NULL;
        while (j < l) {
            if (!SLField(sec, l, &j, &f2, &w2, &s2, &l2)) return NULL;
            if (f2 == SLLyricsField && w2 == 2) return NULL;
        }
    }
    if (!sections) return NULL;   // не похоже на NpvScrollResponse

    // новая секция текста
    SLBuf lyrics = {0}, info = {0}, section = {0}, structure = {0}, out = {0};
    lyrics.ok = info.ok = section.ok = structure.ok = out.ok = 1;
    SLPutLen(&lyrics, 1, trackURI, strlen(trackURI));
    SLPutLen(&info, 1, SLLyricsSectionID, strlen(SLLyricsSectionID));
    SLPutLen(&section, SLLyricsField, lyrics.p, lyrics.len);
    SLPutLen(&section, SLInfoField, info.p, info.len);
    SLPutLen(&structure, SLSectionField, section.p, section.len);
    SLPut(&structure, st, structLen);

    SLPut(&out, in, structFieldStart);
    SLPutLen(&out, SLStructureField, structure.p, structure.len);
    SLPut(&out, in + structFieldEnd, inLen - structFieldEnd);

    int ok = lyrics.ok && info.ok && section.ok && structure.ok && out.ok;
    free(lyrics.p); free(info.p); free(section.p); free(structure.p);
    if (!ok) { free(out.p); return NULL; }
    *outLen = out.len;
    return out.p;
}
