#!/usr/bin/env python3
"""Versioned emotion instructions used by the isolated benchmark."""

from __future__ import annotations

from dataclasses import dataclass


PROMPT_VERSION = "cosyvoice3-zh-v1"
SUPPORTED_INTENSITIES = ("subtle", "clear", "strong")


@dataclass(frozen=True)
class EmotionPrompt:
    emotion: str
    intensity: str
    instruction: str
    version: str = PROMPT_VERSION


_BASE_INSTRUCTIONS = {
    "natural": "使用自然、清晰、克制的普通话表达，保持正常语速和真实呼吸，不额外表演情绪",
    "happy": "用开心而自然的普通话表达，语调明亮，节奏轻快，带真实笑意，不要夸张喊叫",
    "excited": "用兴奋、充满能量的普通话表达，节奏有冲劲，重音鲜明，保持清楚，不要尖叫",
    "sad": "用悲伤但克制的普通话表达，语调低落，节奏稍缓，保留停顿和失落感，不要哭喊",
    "angry": "用愤怒且有压迫感的普通话表达，语气坚定，重音清楚，节奏有力，不要只靠增大音量或失控吼叫",
}

_INTENSITY_PREFIXES = {
    "subtle": "请轻微地",
    "clear": "请明显地",
    "strong": "请强烈但保持清晰地",
}


def build_emotion_prompt(emotion: str, intensity: str = "clear") -> EmotionPrompt:
    normalized_emotion = emotion.strip().lower()
    normalized_intensity = intensity.strip().lower()
    if normalized_emotion not in _BASE_INSTRUCTIONS:
        raise ValueError(f"unsupported emotion: {emotion}")
    if normalized_intensity not in SUPPORTED_INTENSITIES:
        raise ValueError(f"unsupported intensity: {intensity}")

    instruction = (
        f"{_INTENSITY_PREFIXES[normalized_intensity]}{_BASE_INSTRUCTIONS[normalized_emotion]}。"
        "请始终保持参考录音中同一个人的音色与身份。"
    )
    return EmotionPrompt(
        emotion=normalized_emotion,
        intensity=normalized_intensity,
        instruction=instruction,
    )
