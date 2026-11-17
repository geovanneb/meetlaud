// The JNI bridge to llama.cpp. Text goes out as UTF-8 bytes, and Kotlin decodes it, so that a character split
// across two tokens is never cut in half.
#include <jni.h>
#include <android/log.h>
#include <algorithm>
#include <cmath>
#include <mutex>
#include <string>
#include <vector>
#include "llama.h"

namespace {

std::once_flag backend_once;

void quiet_log(ggml_log_level, const char *, void *) {}

void init_backend() {
    std::call_once(backend_once, [] {
        llama_log_set(quiet_log, nullptr);
        llama_backend_init();
    });
}

std::string to_string(JNIEnv *env, jbyteArray bytes) {
    const jsize size = env->GetArrayLength(bytes);
    std::string text(static_cast<size_t>(size), '\0');
    env->GetByteArrayRegion(bytes, 0, size, reinterpret_cast<jbyte *>(text.data()));
    return text;
}

std::vector<llama_token> tokenize(const llama_vocab *vocab, const std::string &text, bool add_special, bool parse_special) {
    int32_t count = -llama_tokenize(vocab, text.data(), static_cast<int32_t>(text.size()), nullptr, 0, add_special, parse_special);
    if (count <= 0) return {};
    std::vector<llama_token> tokens(static_cast<size_t>(count));
    if (llama_tokenize(vocab, text.data(), static_cast<int32_t>(text.size()), tokens.data(), count, add_special, parse_special) < 0) return {};
    return tokens;
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_meetlaud_engines_llama_LlamaNative_load(JNIEnv *env, jobject, jstring path) {
    init_backend();
    const char *file = env->GetStringUTFChars(path, nullptr);
    llama_model_params params = llama_model_default_params();
    // The default load mode maps the file rather than copying it: under pressure the system drops pages instead
    // of killing the app.
    params.n_gpu_layers = 0;
    llama_model *model = llama_model_load_from_file(file, params);
    env->ReleaseStringUTFChars(path, file);
    return reinterpret_cast<jlong>(model);
}

JNIEXPORT void JNICALL
Java_com_meetlaud_engines_llama_LlamaNative_free(JNIEnv *, jobject, jlong handle) {
    if (handle != 0) llama_model_free(reinterpret_cast<llama_model *>(handle));
}

JNIEXPORT jint JNICALL
Java_com_meetlaud_engines_llama_LlamaNative_countTokens(JNIEnv *env, jobject, jlong handle, jbyteArray text) {
    auto *model = reinterpret_cast<llama_model *>(handle);
    return static_cast<jint>(tokenize(llama_model_get_vocab(model), to_string(env, text), true, true).size());
}

// Writes up to maxTokens after the prompt. The sink's onBytes returns false to stop, which is how a cancelled
// coroutine ends the run. Returns the number of tokens written, or a negative number on failure.
JNIEXPORT jint JNICALL
Java_com_meetlaud_engines_llama_LlamaNative_generate(JNIEnv *env, jobject, jlong handle, jbyteArray promptBytes,
                                                     jint maxTokens, jfloat temperature, jint seed, jint threads, jobject sink) {
    auto *model = reinterpret_cast<llama_model *>(handle);
    const llama_vocab *vocab = llama_model_get_vocab(model);
    std::vector<llama_token> prompt = tokenize(vocab, to_string(env, promptBytes), true, true);
    if (prompt.empty()) return -1;

    llama_context_params params = llama_context_default_params();
    params.n_ctx = static_cast<uint32_t>(prompt.size() + maxTokens + 8);
    params.n_batch = 512;
    params.n_ubatch = 512;
    params.n_threads = threads;
    params.n_threads_batch = threads;
    params.no_perf = true;
    llama_context *ctx = llama_init_from_model(model, params);
    if (ctx == nullptr) return -2;

    llama_sampler *sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (temperature <= 0.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    } else {
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(static_cast<uint32_t>(seed)));
    }

    jclass sinkClass = env->GetObjectClass(sink);
    jmethodID onBytes = env->GetMethodID(sinkClass, "onBytes", "([B)Z");
    int written = 0;
    int status = 0;
    bool stopped = false;
    // The prompt goes in by batches no larger than n_batch. A long prompt takes minutes on a slow phone, and the model
    // stays taken until it ends, so the sink is asked between batches, with no bytes, whether to go on.
    jbyteArray nothing = env->NewByteArray(0);
    for (size_t start = 0; start < prompt.size(); start += params.n_batch) {
        const auto count = static_cast<int32_t>(std::min<size_t>(params.n_batch, prompt.size() - start));
        if (llama_decode(ctx, llama_batch_get_one(prompt.data() + start, count)) != 0) {
            status = -3;
            break;
        }
        if (start + params.n_batch < prompt.size()) {
            const jboolean keepGoing = env->CallBooleanMethod(sink, onBytes, nothing);
            if (env->ExceptionCheck() || !keepGoing) {
                stopped = true;
                break;
            }
        }
    }
    env->DeleteLocalRef(nothing);
    char piece[256];
    while (status == 0 && !stopped && written < maxTokens) {
        llama_token token = llama_sampler_sample(sampler, ctx, -1);
        if (llama_vocab_is_eog(vocab, token)) break;
        const int32_t length = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, false);
        if (length > 0) {
            jbyteArray out = env->NewByteArray(length);
            env->SetByteArrayRegion(out, 0, length, reinterpret_cast<const jbyte *>(piece));
            const jboolean keepGoing = env->CallBooleanMethod(sink, onBytes, out);
            env->DeleteLocalRef(out);
            if (env->ExceptionCheck() || !keepGoing) break;
        }
        written += 1;
        if (llama_decode(ctx, llama_batch_get_one(&token, 1)) != 0) status = -3;
    }
    llama_sampler_free(sampler);
    llama_free(ctx);
    return status == 0 ? written : status;
}

// One vector per text, as the model pools it, scaled to unit length. Null when the model cannot embed.
JNIEXPORT jobjectArray JNICALL
Java_com_meetlaud_engines_llama_LlamaNative_embed(JNIEnv *env, jobject, jlong handle, jobjectArray texts, jint maxTokens, jint threads) {
    auto *model = reinterpret_cast<llama_model *>(handle);
    const llama_vocab *vocab = llama_model_get_vocab(model);
    llama_context_params params = llama_context_default_params();
    params.embeddings = true;
    params.n_ctx = static_cast<uint32_t>(maxTokens);
    params.n_batch = static_cast<uint32_t>(maxTokens);
    params.n_ubatch = static_cast<uint32_t>(maxTokens);
    params.n_threads = threads;
    params.n_threads_batch = threads;
    params.no_perf = true;
    llama_context *ctx = llama_init_from_model(model, params);
    if (ctx == nullptr) return nullptr;
    const int dimensions = llama_model_n_embd_out(model) > 0 ? llama_model_n_embd_out(model) : llama_model_n_embd(model);

    const jsize count = env->GetArrayLength(texts);
    jobjectArray result = env->NewObjectArray(count, env->FindClass("[F"), nullptr);
    bool failed = false;
    for (jsize index = 0; index < count && !failed; index++) {
        auto bytes = static_cast<jbyteArray>(env->GetObjectArrayElement(texts, index));
        std::vector<llama_token> tokens = tokenize(vocab, to_string(env, bytes), true, false);
        env->DeleteLocalRef(bytes);
        if (tokens.size() > static_cast<size_t>(maxTokens)) {
            // Keep the end token the model pools on, and drop the middle of an over-long passage.
            const llama_token last = tokens.back();
            tokens.resize(static_cast<size_t>(maxTokens));
            tokens.back() = last;
        }
        llama_memory_clear(llama_get_memory(ctx), true);
        if (tokens.empty() || llama_decode(ctx, llama_batch_get_one(tokens.data(), static_cast<int32_t>(tokens.size()))) != 0) {
            failed = true;
            break;
        }
        const float *vector = llama_get_embeddings_seq(ctx, 0);
        if (vector == nullptr) vector = llama_get_embeddings_ith(ctx, -1);
        if (vector == nullptr) {
            failed = true;
            break;
        }
        double norm = 0;
        for (int i = 0; i < dimensions; i++) norm += static_cast<double>(vector[i]) * vector[i];
        const float scale = norm > 0 ? static_cast<float>(1.0 / std::sqrt(norm)) : 0.0f;
        std::vector<float> unit(static_cast<size_t>(dimensions));
        for (int i = 0; i < dimensions; i++) unit[static_cast<size_t>(i)] = vector[i] * scale;
        jfloatArray out = env->NewFloatArray(dimensions);
        env->SetFloatArrayRegion(out, 0, dimensions, unit.data());
        env->SetObjectArrayElement(result, index, out);
        env->DeleteLocalRef(out);
    }
    llama_free(ctx);
    return failed ? nullptr : result;
}

}  // extern "C"
