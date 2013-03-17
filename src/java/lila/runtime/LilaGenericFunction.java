package lila.runtime;

import java.lang.invoke.MethodHandle;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import lila.runtime.dispatch.Case;
import lila.runtime.dispatch.Method;
import lila.runtime.dispatch.Predicate;

public class LilaGenericFunction extends LilaCallable {

	public static final LilaClass lilaClass =
		new LilaClass(true, "<generic-function>", LilaGenericFunction.class,
		              LilaObject.lilaClass);


	private Map<Predicate,Case> cases = new HashMap<>();

	private List<LilaObject> closedArguments = Collections.emptyList();

	private List<Expression> inputExpressions = Collections.emptyList();

	public Map<Expression,ExpressionInfo> expressionInfo = new HashMap<>();

	// used by dispatch function
	private List<Method> methods = new ArrayList<>();

	public LilaGenericFunction(String name) {
		super(lilaClass, name);
	}

	public LilaGenericFunction(String name, Expression... inputExpressions) {
		this(name);
		// TODO: remove, debugging
		int cost = 0;
		for (Expression inputExpression : inputExpressions)
			inputExpression.cost = cost++;

		this.inputExpressions = Arrays.asList(inputExpressions);
	}

	public Collection<Case> getCases() {
		return this.cases.values();
	}

	public int getArity() {
		return this.inputExpressions.size();
	}

	public List<Expression> getInputExpressions() {
		return inputExpressions;
	}

	public List<Method> getMethods() {
		return methods;
	}

 	public void addMethodHandle(Predicate predicate, MethodHandle handle) {
		addMethod(predicate, new Method(handle));
 	}

 	public void addMethod(Predicate predicate, Method method) {
		for (Predicate conjunction : predicate.canonicalize()) {
			Case c = this.cases.get(conjunction);
			if (c == null) {
				c = new Case(conjunction);
				this.cases.put(conjunction, c);
			}
			c.methods.add(method);
		}
		if (!this.methods.contains(method))
			this.methods.add(method);
	}

	void compileExpressions(Compiler compiler) {
		for (Case c : this.cases.values()) {
			c.conjunction.compileExpressions(compiler);
		}
	};

	// TODO: rename; override in GenericFunction
	//       subclass defined inside interpreter
	LilaGenericFunction copy() {
		return null;
	};

	@Override
	public LilaGenericFunction close(LilaObject value) {
		LilaGenericFunction gf = copy();
		gf.closedArguments = new ArrayList<LilaObject>();
		gf.closedArguments.addAll(this.closedArguments);
		gf.closedArguments.add(value);
		// TODO: copy cases
		return gf;
	}

	@Override
	public LilaObject apply(LilaObject[] arguments) {
		// TODO:
		return null;
	}

	@Override
	public String toString() {
		return String.format("#[GenericFunction %s]", this.getName());
	}

	@Override
	LilaObject fallback
		(LilaCallSite callSite, LilaCallable callable, LilaObject[] args)
		throws Throwable
	{
		// TODO:
		System.out.println("GF CALL");
		return null;
	}

	// NOTE: implemented in interpreter
	MethodHandle getExpressionMethod(Expression expression) {
		return null;
	}

	public void dumpMethods() {
		StringBuilder builder = new StringBuilder();
		String sep = "  ";
		for (Case c : this.cases.values()) {
			builder.append(String.format("\n  %s %s => %s", sep,
			                             c.conjunction, c.methods));
			sep = "or";
		}
		System.err.println("GF" + builder);
	}


}
