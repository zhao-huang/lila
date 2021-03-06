package lila.runtime;

import static java.lang.invoke.MethodType.methodType;

import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodHandles.Lookup;
import java.lang.invoke.MethodType;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Random;

public class Core {

	static final Lookup lookup = MethodHandles.lookup();

	static LilaFunction exportFunction
		(String exportedName, String name, MethodType type)
	{
		LilaFunction function =
			LilaFunction.wrap(Core.class, name, type, exportedName);
		RT.ENV.put(exportedName, function);
		return function;
	}

	static LilaFunction exportFunction(String name, MethodType type) {
		return exportFunction(name, name, type);
	}

	static void exportClass(LilaClass c) {
		RT.ENV.put(c.name, c);
	}

	static void initialize() {
		RT.ENV.put("*lila-version*", new LilaString("0.1"));
		exportClass(LilaObject.lilaClass);
		exportClass(LilaClass.lilaClass);
		exportClass(LilaNegatedClass.lilaClass);
		exportClass(LilaBoolean.lilaClass);
		exportClass(LilaFalse.lilaClass);
		exportClass(LilaTrue.lilaClass);
		exportClass(LilaFunction.lilaClass);
		exportClass(LilaMultiMethod.lilaClass);
		exportClass(LilaPredicateMethod.lilaClass);
		exportClass(LilaInteger.lilaClass);
		exportClass(LilaString.lilaClass);
	}

	//// functions


	// not

	static LilaBoolean not(LilaObject object) {
		return LilaBoolean.box(!object.isTrue());
	}

	static {
		exportFunction("not", methodType(LilaBoolean.class,
		                                 LilaObject.class));

	}

	// assert

	static LilaBoolean assertTrue(LilaObject object) {
		if (!object.isTrue())
			throw new AssertionError();
		return LilaBoolean.TRUE;
	}

	static {
		exportFunction("assert", "assertTrue",
		               methodType(LilaBoolean.class,
		                          LilaObject.class));
	}

	// print

	static LilaString print(LilaString string) {
		System.out.println(string.string);
		return string;
	}

	static {
		exportFunction("print", methodType(LilaString.class,
		                                   LilaString.class));
	}

	// as-string

	static LilaString asString(LilaObject value) {
		return new LilaString(value.toString());
	}

	static {
		exportFunction("as-string", "asString",
		               methodType(LilaString.class,
		                          LilaObject.class));
	}


	// +

	static LilaInteger plus(LilaInteger a, LilaInteger b) {
		return new LilaInteger(a.value + b.value);
	}

	static {
		exportFunction("+", "plus",
		               methodType(LilaInteger.class,
		                          LilaInteger.class, LilaInteger.class));
	}


	// -

	static LilaInteger minus(LilaInteger a, LilaInteger b) {
		return new LilaInteger(a.value - b.value);
	}

	static {
		exportFunction("-", "minus",
		               methodType(LilaInteger.class,
		                          LilaInteger.class, LilaInteger.class));
	}

	// <

	static LilaBoolean lessThan(LilaInteger a, LilaInteger b) {
		return LilaBoolean.box(a.value < b.value);
	}

	static {
		exportFunction("<", "lessThan",
		               methodType(LilaBoolean.class,
		                          LilaInteger.class, LilaInteger.class));
	}


	// random-argument

	static LilaObject randomArgument(LilaObject ignored, LilaArray rest) {
		Random random = new Random();
		LilaObject[] objects = rest.array;
		return objects[random.nextInt(objects.length)];
	}

	static {
		LilaFunction randomArgument =
			exportFunction("random-argument", "randomArgument",
			               methodType(LilaObject.class,
			                          LilaObject.class, LilaArray.class));
		randomArgument.setVariadic(true);
	}

	// random-element

	static Random random = new Random();

	static LilaObject randomElement(LilaArray elements) {
		LilaObject[] objects = elements.array;
		return objects[random.nextInt(objects.length)];
	}

	static {
		exportFunction("random-element", "randomElement",
		               methodType(LilaObject.class, LilaArray.class));
	}

	// initialize

	static LilaObject initializeLilaObject(LilaObject nextMethod, LilaObject object, LilaArray rest) {
		String[] properties = object.getType().classProperties;
		for (int i = 0; i < rest.array.length && i < properties.length; i++)
			object.setProperty(properties[i], rest.array[i]);
		return object;
	}

	static LilaMultiMethod initialize;
	static {
		MethodHandle initializeLilaObject = null;
		try {
			initializeLilaObject = lookup
				.findStatic(Core.class, "initializeLilaObject",
				            methodType(LilaObject.class,
				                       LilaObject.class, LilaObject.class, LilaArray.class));
		} catch (Throwable e) {
			throw (AssertionError) new AssertionError().initCause(e);
		}

		initialize = new LilaMultiMethod("initialize", 1);
		initialize.setVariadic(true);
		initialize.addMethod(new LilaClass[] { LilaObject.lilaClass },
		                     initializeLilaObject);
		RT.setValue("initialize", initialize);
	}

	// make

	static final MethodType builtinMakeType =
		methodType(LilaObject.class,
		           LilaObject[].class);

	static LilaObject make(LilaClass lilaClass, LilaArray rest)
		throws Throwable
	{
		Class<?> javaClass = lilaClass.getJavaClass();
		LilaObject object = null;
		if (lilaClass.isBuiltin()) {
			MethodHandle mh = lookup
				.findStatic(javaClass, "make", builtinMakeType);
			object = (LilaObject)mh.invokeExact(rest.array);
		} else {
			object = new LilaObject(lilaClass);
			LilaObject[] args = new LilaObject[rest.array.length + 1];
			args[0] = object;
			System.arraycopy(rest.array, 0, args, 1, rest.array.length);
			initialize.apply(args);
		}
		return object;
	}

	static {
		LilaFunction make =
			exportFunction("make",
			               methodType(LilaObject.class,
			                          LilaClass.class, LilaArray.class));
		make.setVariadic(true);
	}


	// object-class

	static LilaClass objectClass(LilaObject object) {
		return object.getType();
	}

	static {
		exportFunction("object-class", "objectClass",
		               methodType(LilaClass.class,
		                          LilaObject.class));
	}


	// subtype?

	static LilaBoolean isSubtypeOf(LilaClass a, LilaClass b) {
		return LilaBoolean.box(a.isSubtypeOf(b));
	}

	static {
		exportFunction("subtype?", "isSubtypeOf",
		               methodType(LilaBoolean.class,
		                          LilaClass.class, LilaClass.class));
	}


	// instance?

	static LilaBoolean isInstanceOf(LilaObject object, LilaClass type) {
		return LilaBoolean.box(type.isInstance(object));
	}

	static {
		exportFunction("instance?", "isInstanceOf",
		               methodType(LilaBoolean.class,
		                          LilaObject.class, LilaClass.class));
	}



	// make-array

	static LilaArray makeArray(LilaArray rest) {
		return rest;
	}

	static {
		LilaFunction makeArray =
			exportFunction("make-array", "makeArray",
			               methodType(LilaArray.class,
			                          LilaArray.class));
		makeArray.setVariadic(true);
	}

	// ==

	static LilaBoolean equals(LilaObject object, LilaObject other) {
		return LilaBoolean.box(object.equals(other));
	}

	static {
		exportFunction("==", "equals",
		               methodType(LilaBoolean.class,
		                          LilaObject.class, LilaObject.class));
	}

	// apply

	// TODO: make generic for LilaCallable
	static LilaObject apply(LilaCallable callable, LilaArray arguments) {
		return callable.apply(arguments.array);
	}

	static {
		exportFunction("apply",
		               methodType(LilaObject.class,
		                          LilaCallable.class, LilaArray.class));
	}

	// get

	static LilaObject get(LilaObject object, LilaString property) {
		return object.getProperty(property.string);
	}

	static {
		exportFunction("get",
		               methodType(LilaObject.class,
		                          LilaObject.class, LilaString.class));
	}

	// set!

	static LilaObject set(LilaObject object, LilaString property, LilaObject value) {
		object.setProperty(property.string, value);
		return value;
	}

	static {
		exportFunction("set!", "set",
		               methodType(LilaObject.class,
		                          LilaObject.class, LilaString.class, LilaObject.class));
	}

	// inc!

	static LilaInteger inc(LilaObject object, LilaString property) {
		LilaObject value = object.getProperty(property.string);
		long currentValue = (value instanceof LilaInteger
							 ? (long)value.getJavaValue()
							 : 0);
		LilaInteger newValue = new LilaInteger(currentValue + 1);
		object.setProperty(property.string, newValue);
		return newValue;
	}

	static {
		exportFunction("inc!", "inc",
		               methodType(LilaInteger.class,
		                          LilaObject.class, LilaString.class));
	}


	// time

	static LilaInteger time() {
		return new LilaInteger(System.currentTimeMillis());
	}

	static {
		exportFunction("time",
		               methodType(LilaInteger.class));
	}

	// concatenate

	static LilaArray concatenate(LilaArray first, LilaArray others) {
		int length = first.array.length;
		for (LilaObject other : others.array) {
			LilaArray otherArray = (LilaArray)other;
			length += otherArray.array.length;
		}
		LilaObject[] result = Arrays.copyOf(first.array, length);
		int index = first.array.length;
		for (LilaObject other : others.array) {
			LilaArray otherArray = (LilaArray)other;
			int count = otherArray.array.length;
			System.arraycopy(otherArray.array, 0, result, index, count);
			index += count;
		}
		return new LilaArray(result);
	}

	static {
		LilaFunction concatenate =
			exportFunction("concatenate",
			               methodType(LilaArray.class,
			                          LilaArray.class, LilaArray.class));
		concatenate.setVariadic(true);
	}
	
	
	// benchmark
	
	static LilaBoolean benchmark(LilaFunction fn, LilaInteger count) throws Throwable {
		long n = count.value;
		for (int j = 0; j < n; j++) {
			long startTime = System.nanoTime();
			LilaObject ignored = (LilaObject)fn.methodHandle.invokeExact();
			long stopTime = System.nanoTime();
			long runTime = stopTime - startTime;
			System.out.println(runTime / 1000000);
		}
		return LilaBoolean.FALSE;
	}
	
	static {
		exportFunction("benchmark",
		               methodType(LilaBoolean.class, 
		                          LilaFunction.class, LilaInteger.class));
	}
	
	// nth
	
	static LilaObject nth(LilaInteger pos, LilaArray array)  {
		return array.array[(int)pos.value];
	}
	
	static {
		exportFunction("nth",
		               methodType(LilaObject.class, 
		                          LilaInteger.class, LilaArray.class));
	}
}
