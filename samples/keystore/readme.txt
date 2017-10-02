-- NOTICE: study_android_ndk.keystore use password: study_android_ndk

-- use jdk/bin/keytool generate keystore
-- 
<jdk>/bin/keytool -genkey -v -keystore study_android_ndk.keystore -alias "StudyAndroidNDK" -keyalg RSA -validity 40000

-- use jarsigner
-- 
jarsigner -keystore study_android_ndk.keystore -storepass "study_android_ndk" -keypass "study_android_ndk" -signedjar=output.apk input.ap_ "StudyAndroidNDK"


