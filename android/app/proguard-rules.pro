# ML Kit text recognition: only the Latin-script model is bundled. The
# plugin references the other scripts' option classes, which are not on
# the classpath, so R8 must not fail on them.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
