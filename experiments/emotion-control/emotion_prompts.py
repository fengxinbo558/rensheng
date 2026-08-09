#!/usr/bin/env python3
"""Versioned emotion instructions used by the isolated benchmark."""

from __future__ import annotations

from dataclasses import dataclass


PROMPT_VERSION = "cosyvoice3-zh-v2-conversational"
SUPPORTED_INTENSITIES = ("subtle", "clear", "strong")


@dataclass(frozen=True)
class EmotionPrompt:
    emotion: str
    intensity: str
    instruction: str
    version: str = PROMPT_VERSION


_BASE_INSTRUCTIONS = {
    "natural": "像面对熟悉的人正常说话，语速、音高和力度接近参考录音，不要播音、朗诵或表演",
    "happy": "保持日常对话，只让人听出心情不错，声音略微轻松，不要刻意笑、不要广告腔或舞台腔",
    "excited": "保持日常对话，只比平时更有精神，语速和重音只略微变化，不要喊叫、不要夸大重音或故意加速",
    "sad": "像在日常谈话中克制住失落，声音略微低沉、停顿自然，不要哭腔、拖腔或故意压嗓",
    "angry": "表达冷静而明确的不满，只在关键词上略微加重，不要吼叫、咬牙、压嗓或制造压迫性的表演感",
}

_INTENSITY_PREFIXES = {
    "subtle": "只带一点情绪，",
    "clear": "情绪清楚但不过度，",
    "strong": "情绪更强一些，但仍像真实对话，",
}


def build_emotion_prompt(emotion: str, intensity: str = "clear") -> EmotionPrompt:
    normalized_emotion = emotion.strip().lower()
    normalized_intensity = intensity.strip().lower()
    if normalized_emotion not in _BASE_INSTRUCTIONS:
        raise ValueError(f"unsupported emotion: {emotion}")
    if normalized_intensity not in SUPPORTED_INTENSITIES:
        raise ValueError(f"unsupported intensity: {intensity}")

    if normalized_emotion == "natural":
        expression = _BASE_INSTRUCTIONS[normalized_emotion]
    else:
        expression = (
            f"{_INTENSITY_PREFIXES[normalized_intensity]}"
            f"{_BASE_INSTRUCTIONS[normalized_emotion]}"
        )
    instruction = f"{expression}。请始终保持参考录音中同一个人的音色与身份。"
    return EmotionPrompt(
        emotion=normalized_emotion,
        intensity=normalized_intensity,
        instruction=instruction,
    )
