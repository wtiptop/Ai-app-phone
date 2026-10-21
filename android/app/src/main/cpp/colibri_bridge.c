// Port Scalającej: stdin/stdout należą wyłącznie do procesu :colibri.
// Kod upstream pozostaje bez zmian; każda generacja dostaje nowy proces.
#include <jni.h>
#include <fcntl.h>
#include <unistd.h>
#define main scalajaca_colibri_main
#include "olmoe.c"
#undef main

JNIEXPORT jint JNICALL
Java_pl_scalajaca_scalajaca_colibri_ColibriService_runNative(
    JNIEnv *env, jobject service, jstring directory, jint input, jint output,
    jint context) {
    (void)service;
    const char *path = (*env)->GetStringUTFChars(env, directory, NULL);
    if (!path) return 1;
    setenv("SNAP", path, 1);
    (*env)->ReleaseStringUTFChars(env, directory, path);
    char ctx[16]; snprintf(ctx, sizeof ctx, "%d", context);
    setenv("SERVE", "1", 1); // lokalny protokół potoków, bez serwera HTTP
    setenv("CTX", ctx, 1);
    setenv("KV_SLOTS", "1", 1);
    setenv("PILOT", "0", 1);
    setenv("IDOT", "0", 1);
    if (dup2(input, STDIN_FILENO) < 0 || dup2(output, STDOUT_FILENO) < 0) return 2;
    int quiet = open("/dev/null", O_WRONLY);
    if (quiet >= 0) { dup2(quiet, STDERR_FILENO); close(quiet); }
    clearerr(stdin); clearerr(stdout);
    char *args[] = {"colibri-olmoe", "2", "8", NULL};
    return scalajaca_colibri_main(3, args);
}
