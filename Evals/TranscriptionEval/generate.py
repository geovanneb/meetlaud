#!/usr/bin/env python3
"""Generate fictional speech locally with macOS voices; audio and results belong in build/, never Git."""
import array
import json
from pathlib import Path
import random
import re
import subprocess
import sys
import wave

SCRIPTS = {
    "en": ("Samantha", "Today we reviewed the garden project. The team approved the smaller design. The budget is eight thousand dollars. The first task is to check the materials by Friday. The second task is to send the revised plan on Monday. We have not approved the delivery date. That question remains open until the supplier confirms the schedule. The next meeting is on Tuesday. Please keep the original notes and verify every action before sharing the summary."),
    "pt": ("Luciana", "Hoje revisamos o projeto do jardim. A equipe aprovou o desenho menor. O orçamento é de oito mil reais. A primeira tarefa é verificar os materiais até sexta-feira. A segunda tarefa é enviar o plano revisado na segunda-feira. Ainda não aprovamos a data de entrega. Essa pergunta continua aberta até que o fornecedor confirme o cronograma. A próxima reunião será na terça-feira. Por favor, mantenha as anotações originais e verifique cada tarefa antes de compartilhar o resumo."),
    "es": ("Mónica", "Hoy revisamos el proyecto del jardín. El equipo aprobó el diseño más pequeño. El presupuesto es de ocho mil euros. La primera tarea es revisar los materiales antes del viernes. La segunda tarea es enviar el plan revisado el lunes. No hemos aprobado la fecha de entrega. Esa pregunta sigue abierta hasta que el proveedor confirme el calendario. La próxima reunión será el martes. Por favor, guarda las notas originales y verifica cada tarea antes de compartir el resumen."),
    "ja": ("Kyoko", "今日は庭の計画を確認しました。チームは小さい設計を承認しました。予算は八万円です。最初の作業は金曜日までに材料を確認することです。次の作業は月曜日に修正した計画を送ることです。納品日はまだ承認していません。業者が日程を確認するまで、この質問は未解決です。次の会議は火曜日です。元のメモを残して、要約を共有する前にすべての作業を確認してください。"),
}


def write_audio(path, samples):
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(16000)
        output.writeframes(samples.tobytes())


def main():
    folder = Path(sys.argv[1]).resolve()
    folder.mkdir(parents=True, exist_ok=True)
    # `say` can silently fall back to another language for an unknown voice name.
    available = subprocess.run(["say", "-v", "?"], check=True, capture_output=True, text=True).stdout
    voices = set(re.findall(r"^(.+?)\s+[a-z]{2}_[A-Z]{2}\s+#", available, re.MULTILINE))
    missing = [voice for voice, _ in SCRIPTS.values() if voice not in voices]
    if missing:
        raise SystemExit(f"Install these system voices before evaluating: {missing}")
    fixtures = []
    for language, (voice, reference) in SCRIPTS.items():
        script = folder / f"{language}.txt"
        script.write_text(reference)
        subprocess.run(["say", "-v", voice, "-r", "155", "-f", str(script), "-o", str(folder / f"{language}.wav"),
                        "--file-format=WAVE", "--data-format=LEI16@16000"], check=True)
        fixtures.append(dict(id=language, language=language, audio=f"{language}.wav", reference=reference))
    with wave.open(str(folder / "en.wav"), "rb") as source:
        samples = array.array("h", source.readframes(source.getnframes()))
    rng = random.Random(42)
    quiet = array.array("h", (int(value * 0.08) + rng.randint(-16, 16) for value in samples))
    write_audio(folder / "en-quiet.wav", quiet)
    fixtures.append(dict(id="en-quiet", language="en", audio="en-quiet.wav", reference=SCRIPTS["en"][1]))
    # More than two three-minute windows, including pauses between repetitions.
    repeated = (samples + array.array("h", [0] * 16000)) * 14
    write_audio(folder / "en-long.wav", repeated)
    fixtures.append(dict(id="en-long", language="en", audio="en-long.wav", reference=" ".join([SCRIPTS["en"][1]] * 14)))
    # The way the app runs by default: the first window finds the language, the ones after it are told, and
    # vocabulary spellings go along as hints. Windows after the first once came back empty on this path.
    fixtures.append(dict(
        id="en-long-app", language="en", audio="en-long.wav", reference=" ".join([SCRIPTS["en"][1]] * 14),
        hints=["Garden Project", "Marlow Supply"], detectsLanguage=True,
    ))
    write_audio(folder / "silence.wav", array.array("h", [0] * 16000 * 10))
    fixtures.append(dict(id="silence", language="en", audio="silence.wav", reference=""))
    (folder / "fixtures.json").write_text(json.dumps(fixtures, ensure_ascii=False, indent=2))
    print(folder / "fixtures.json")


if __name__ == "__main__":
    main()
