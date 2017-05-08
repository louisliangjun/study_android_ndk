// t1.cpp

#include "t1_androidos_jni_JNI.h"

#include <stdio.h>

JNIEXPORT void JNICALL Java_t1_androidos_jni_JNI_test1
  (JNIEnv *, jobject)
{
	fprintf(stderr, "test\n");
}

