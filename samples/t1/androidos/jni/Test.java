package t1.androidos.jni;

import android.app.Activity;

public class Test extends Activity {

	static {
		System.loadLibrary("t1_jni");
	}

	public void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		setContentView(R.layout.main);
		JNI t1 = new JNI();
		t1.test();
	}
}
