#include "local_engine.h"
#include <jni.h>
#include <memory>
#include <mutex>

static std::mutex state_mutex, generation_mutex;
static jlong active_token = 0;
static std::shared_ptr<scalajaca::Control> active;
static std::string utf(JNIEnv * env, jstring str) {
    const char * data = env->GetStringUTFChars(str, nullptr);
    if (!data) throw std::bad_alloc();
    std::string out(data); env->ReleaseStringUTFChars(str, data); return out;
}
extern "C" JNIEXPORT jstring JNICALL Java_pl_scalajaca_scalajaca_local_NativeLlama_version(JNIEnv * env, jobject) {
    return env->NewStringUTF(scalajaca::ENGINE_COMMIT);
}
extern "C" JNIEXPORT void JNICALL Java_pl_scalajaca_scalajaca_local_NativeLlama_prepare(JNIEnv * env, jobject, jlong token) {
    try {
        auto next = std::make_shared<scalajaca::Control>();
        std::lock_guard<std::mutex> guard(state_mutex);
        active_token = token; active = std::move(next);
    } catch (const std::bad_alloc &) {
        auto cls = env->FindClass("java/lang/OutOfMemoryError");
        if (cls) env->ThrowNew(cls, "Brak pamieci silnika lokalnego.");
    }
}
extern "C" JNIEXPORT void JNICALL Java_pl_scalajaca_scalajaca_local_NativeLlama_cancel(JNIEnv *, jobject, jlong token) {
    std::lock_guard<std::mutex> guard(state_mutex);
    if (active && active_token == token) active->cancelled = true;
}
extern "C" JNIEXPORT jstring JNICALL Java_pl_scalajaca_scalajaca_local_NativeLlama_generate(
    JNIEnv * env, jobject, jlong token, jstring path, jstring profile, jbyteArray messages, jint context, jint limit, jobject sink) {
    std::unique_lock<std::mutex> lock(generation_mutex, std::try_to_lock);
    if (!lock.owns_lock()) return env->NewStringUTF("{\"error\":\"busy\"}");
    std::shared_ptr<scalajaca::Control> control;
    { std::lock_guard<std::mutex> guard(state_mutex); if (token == active_token) control = active; }
    if (!control) return env->NewStringUTF("{\"error\":\"cancelled\"}");
    try {
        auto cls = env->GetObjectClass(sink);
        auto callback = env->GetMethodID(cls, "onBytes", "([B)V");
        if (!callback || env->ExceptionCheck()) return nullptr;
        const jsize size = env->GetArrayLength(messages);
        if (size > 65536) throw scalajaca::Failure("invalid_request");
        std::string input((size_t)size, '\0');
        env->GetByteArrayRegion(messages, 0, size, reinterpret_cast<jbyte *>(input.data()));
        auto result = scalajaca::generate(utf(env, path), utf(env, profile), input, context, limit, *control,
            [&](const std::string & bytes) {
                auto buffer = env->NewByteArray((jsize)bytes.size());
                if (!buffer) throw std::bad_alloc();
                env->SetByteArrayRegion(buffer, 0, (jsize)bytes.size(), reinterpret_cast<const jbyte *>(bytes.data()));
                env->CallVoidMethod(sink, callback, buffer); env->DeleteLocalRef(buffer);
                if (env->ExceptionCheck()) throw scalajaca::Failure("callback");
            });
        std::string output = "{\"finish_reason\":\"" + result.reason + "\",\"input_tokens\":" + std::to_string(result.input) + ",\"output_tokens\":" + std::to_string(result.output) + "}";
        return env->NewStringUTF(output.c_str());
    } catch (const scalajaca::Failure & ex) {
        if (env->ExceptionCheck()) return nullptr;
        const std::string output = "{\"error\":\"" + std::string(ex.what()) + "\"}";
        return env->NewStringUTF(output.c_str());
    } catch (const std::bad_alloc &) { return env->ExceptionCheck() ? nullptr : env->NewStringUTF("{\"error\":\"memory\"}");
    } catch (...) { return env->ExceptionCheck() ? nullptr : env->NewStringUTF("{\"error\":\"native_error\"}"); }
}
