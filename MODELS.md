# Similar LLMs for Mobile (GGUF)

Alternatives to the current **MobileLLM 1B Q8_0** (~1.11 GB) for on-device phone use. All available as GGUF and compatible with llama.cpp, Ollama, LM Studio, and MLX-LM.

## Same size class (~0.6–2 GB)

| Model | Params | Best Quant for Phone | Strengths |
|---|---|---|---|
| **MobileLLM-1B / 1.5B** (Meta) | 1B / 1.5B | Q4_K_M (634 MB / 1.1 GB) | Designed for phones from the ground up; current source |
| **Llama 3.2 1B / 3B Instruct** | 1B / 3B | Q4_K_M / Q8_0 | Meta's official mobile-tier; strong instruction following |
| **Gemma 3 1B / 4B** | 1B / 4B | Q4_K_M | Newest Google small model, very strong for size |
| **Qwen 2.5 1.5B Instruct** | 1.5B | Q8_0 | Great multilingual |
| **Qwen3 1.7B** | 1.7B | Q8_0 (~1.7 GB) | Newer Qwen generation |
| **SmolLM2 1.7B Instruct** | 1.7B | Q4_K_M (~1 GB) | Built specifically for on-device |
| **Phi-3.5-mini Instruct** | 3.8B | Q4_K_M (~2.2 GB) | Punches above its weight; Microsoft |
| **TinyLlama 1.1B Chat** | 1.1B | Q8_0 (~1.1 GB) | Smallest viable chat model |

## Where to download (GGUF)

- [MobileLLM-1B-GGUF (current source)](https://huggingface.co/pjh64/MobileLLM_1B-GGUF)
- [Llama-3.2-1B-Instruct-GGUF](https://huggingface.co/unsloth/Llama-3.2-1B-Instruct-GGUF) / [3B](https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF)
- [Gemma-3-1B-IT-GGUF](https://huggingface.co/unsloth/gemma-3-1b-it-GGUF) / [4B](https://huggingface.co/unsloth/gemma-3-4b-it-GGUF)
- [Qwen2.5-1.5B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF)
- [Qwen3-1.7B-GGUF](https://huggingface.co/Qwen/Qwen3-1.7B-GGUF)
- [SmolLM2-1.7B-Instruct-GGUF](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF)
- [Phi-3.5-mini-instruct-GGUF](https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF)
- [TinyLlama-1.1B-Chat-GGUF](https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF)

## Quick picks

- **Closest to the current MobileLLM 1B sweet spot** → MobileLLM 1.5B Q4_K_M or Llama 3.2 1B Q8_0
- **Best raw quality at this size** → Gemma 3 4B (Q4_K_M, ~2.5 GB) or Phi-3.5-mini
- **Smallest footprint** → MobileLLM-1B (Q4_K_M, 634 MB) or Llama 3.2 1B
- **Best multilingual** → Qwen 2.5 1.5B Instruct (Q8_0)

## Sources

- [MobileLLM-1B-GGUF (current source)](https://huggingface.co/pjh64/MobileLLM_1B-GGUF)
- [facebook.MobileLLM-1.5B-GGUF](https://huggingface.co/neootaku/facebook.MobileLLM-1.5B-GGUF)
- [Qwen3-1.7B-GGUF](https://huggingface.co/Qwen/Qwen3-1.7B-GGUF)
- [SmolLM-1.7B-GGUF](https://huggingface.co/mradermacher/SmolLM-1.7B-GGUF)
- [MobileVLM-1.7B-GGUF](https://huggingface.co/guinmoon/MobileVLM-1.7B-GGUF)
