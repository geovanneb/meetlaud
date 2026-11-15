// The JNI bridge to whisper.cpp. Segments go out one by one to a Kotlin sink, with their text as UTF-8 bytes.
#include <jni.h>
#include <cstring>
#include <string>
#include "whisper.h"

namespace {

void quiet_log(ggml_log_level, const char *, void *) {}

struct Callbacks {
    JNIEnv *env;
    jobject sink;
    jmethodID onProgress;
    jmethodID isCancelled;
};

void on_progress(whisper_context *, whisper_state *, int progress, void *data) {
    auto *callbacks = static_cast<Callbacks *>(data);
    callbacks->env->CallVoidMethod(callbacks->sink, callbacks->onProgress, progress);
}

bool should_abort(void *data) {
    auto *callbacks = static_cast<Callbacks *>(data);
    return callbacks->env->CallBooleanMethod(callbacks->sink, callbacks->isCancelled) == JNI_TRUE;
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_meetlaud_engines_whisper_WhisperNative_load(JNIEnv *env, jobject, jstring path) {
    whisper_log_set(quiet_log, nullptr);
    const char *file = env->GetStringUTFChars(path, nullptr);
    whisper_context_params params = whisper_context_default_params();
    params.use_gpu = false;
    params.flash_attn = true;
    whisper_context *ctx = whisper_init_from_file_with_params(file, params);
    env->ReleaseStringUTFChars(path, file);
    return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT void JNICALL
Java_com_meetlaud_engines_whisper_WhisperNative_free(JNIEnv *, jobject, jlong handle) {
    if (handle != 0) whisper_free(reinterpret_cast<whisper_context *>(handle));
}

// Transcribes 16 kHz mono samples. Each segment reaches the sink's onSegment as start and end in milliseconds and
// UTF-8 text. Returns the language it heard or was given, or null when the run failed or was cancelled.
JNIEXPORT jstring JNICALL
Java_com_meetlaud_engines_whisper_WhisperNative_transcribe(JNIEnv *env, jobject, jlong handle, jfloatArray samples,
                                                           jstring language, jint threads, jobject sink) {
    auto *ctx = reinterpret_cast<whisper_context *>(handle);
    jclass sinkClass = env->GetObjectClass(sink);
    Callbacks callbacks{env, sink, env->GetMethodID(sinkClass, "onProgress", "(I)V"), env->GetMethodID(sinkClass, "isCancelled", "()Z")};
    jmethodID onSegment = env->GetMethodID(sinkClass, "onSegment", "(JJ[B)V");

    std::string code;
    if (language != nullptr) {
        const char *chars = env->GetStringUTFChars(language, nullptr);
        code = chars;
        env->ReleaseStringUTFChars(language, chars);
    }

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = threads;
    params.translate = false;
    params.language = code.empty() ? "auto" : code.c_str();
    params.detect_language = false;
    params.no_context = true;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.print_special = false;
    params.suppress_blank = true;
    params.progress_callback = on_progress;
    params.progress_callback_user_data = &callbacks;
    params.abort_callback = should_abort;
    params.abort_callback_user_data = &callbacks;

    const jsize count = env->GetArrayLength(samples);
    jfloat *audio = env->GetFloatArrayElements(samples, nullptr);
    const int status = whisper_full(ctx, params, audio, count);
    env->ReleaseFloatArrayElements(samples, audio, JNI_ABORT);
    if (status != 0 || env->ExceptionCheck()) return nullptr;

    const int segments = whisper_full_n_segments(ctx);
    for (int i = 0; i < segments; i++) {
        const char *text = whisper_full_get_segment_text(ctx, i);
        const auto length = static_cast<jsize>(std::strlen(text));
        jbyteArray bytes = env->NewByteArray(length);
        env->SetByteArrayRegion(bytes, 0, length, reinterpret_cast<const jbyte *>(text));
        // Whisper counts time in hundredths of a second.
        env->CallVoidMethod(sink, onSegment, static_cast<jlong>(whisper_full_get_segment_t0(ctx, i) * 10),
                            static_cast<jlong>(whisper_full_get_segment_t1(ctx, i) * 10), bytes);
        env->DeleteLocalRef(bytes);
    }
    const int id = whisper_full_lang_id(ctx);
    const char *heard = id >= 0 ? whisper_lang_str(id) : nullptr;
    return env->NewStringUTF(heard != nullptr ? heard : code.c_str());
}

}  // extern "C"
