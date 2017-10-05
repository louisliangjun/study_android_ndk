// main.c

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
 
#include <android/log.h>

#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, "hello", __VA_ARGS__))

int main(int argc, char* argv[]) {
	int i;

	for( i=0; i<100000; ++i ) {
		fprintf(stderr, "hello stderr\n");
		LOGI("hello info\n");
		usleep(1*1000*1000);
	}

	return 0;
}

