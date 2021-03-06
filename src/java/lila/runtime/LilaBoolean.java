package lila.runtime;

public abstract class LilaBoolean extends LilaObject {

	public static final LilaClass lilaClass;
	static {
		lilaClass = new LilaClass(true, "<boolean>", LilaBoolean.class,
		                          LilaObject.lilaClass);
		LilaClass.updateMultiMethods(lilaClass);
	}

	public static LilaBoolean TRUE = new LilaTrue();
	public static LilaBoolean FALSE = new LilaFalse();

	protected boolean value;

	protected LilaBoolean(LilaClass type, boolean value) {
		super(type);
		this.value = value;
	}

	public static LilaBoolean box(boolean value) {
		return value ? TRUE : FALSE;
	}

	@Override
	public Object getJavaValue() {
		return this.value;
	}

	@Override
	public boolean isTrue() {
		return this.value;
	}

	@Override
	public String toString() {
		return this.value + "";
	}
}
