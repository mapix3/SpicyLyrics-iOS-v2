#ifndef SLScrollsita_h
#define SLScrollsita_h

#include <stddef.h>
#include <stdint.h>

/// Ответ scrollsita/v1/scroll (NpvScrollResponse) — набор карточек под плеером, который присылает сервер.
/// Если в нём нет секции текста, добавляет её первой:
///   structure(1) { section(1) { lyrics(5) { uri(1): "spotify:track:<id>" }, info(23) { id(1): <lyrics section> } } }
/// Возвращает новый буфер (освободить free()) и его длину в *outLen, или NULL — если менять не нужно / формат не тот.
uint8_t *SLScrollsitaAddLyrics(const uint8_t *in, size_t inLen, const char *trackURI, size_t *outLen);

#endif
