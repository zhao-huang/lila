require 'rubygems'
require 'bitescript/bytecode'
require 'java'

java_import 'lila.runtime.LilaObject'
java_import 'lila.runtime.LilaString'
java_import 'lila.runtime.LilaInteger'
java_import 'lila.runtime.LilaBoolean'
java_import 'lila.runtime.LilaFunction'
java_import 'lila.runtime.LilaArray'
java_import 'lila.runtime.RT'
java_import 'lila.runtime.StringNames'
# NOTE: monkey patching java classes has several
# limitations, so shadow and subclass instead
java_import 'lila.runtime.Expression' do
  'InternalExpression'
end
java_import 'lila.runtime.LilaMultiMethod'
java_import 'lila.runtime.LilaPredicateMethod'
java_import 'lila.runtime.ExpressionInfo'


java_import 'java.lang.invoke.MethodType'
java_import 'java.lang.invoke.MethodHandle'
java_import 'java.lang.invoke.CallSite'
java_import 'java.lang.invoke.MethodHandles$Lookup'


def gensym
  $gensym||=0
  $gensym += 1
  ('__' + $gensym.to_s).to_sym
end

module Lila

  class Program < Struct.new :statements; end

  class MultiMethodDefinition < Struct.new \
    :name, :parameter_list, :expressions

    def interpret(interpreter)
      required = self.parameter_list.parameters.dup
      if self.parameter_list.rest
        required.pop
      end
      arity = required.length
      # add next-method parameter
      next_method = Parameter.new 'next-method'
      self.parameter_list.parameters.unshift next_method
      # create actual function
      function = interpreter.eval \
        Function.new(self.name, self.parameter_list, self.expressions)
      # evaluate specializer expressions

      specializers = required.map { |parameter|
        if parameter.type
          interpreter.eval parameter.type
        else
          LilaObject.lilaClass
        end
      }.to_java LilaClass
      # add method to implicit generic function
      mm = RT.getValue self.name
      unless mm.instance_of? LilaMultiMethod
        mm = LilaMultiMethod.new self.name, arity
        mm.setVariadic self.parameter_list.rest
        RT.setValue self.name, mm
      end
      # add method
      mm.addMethod specializers, function.javaValue
      puts mm
    end
    
    def compile(context, builder)
      required = self.parameter_list.parameters.dup
      if self.parameter_list.rest
        required.pop
      end
      arity = required.length
      # add next-method parameter
      next_method = Parameter.new 'next-method'
      self.parameter_list.parameters.unshift next_method 
      # get current value
      builder.ldc self.name
      builder.invokestatic RT, 'getValue', 
        [LilaObject, Java::java.lang.String]
      builder.dup
      builder.instanceof LilaMultiMethod
      label = gensym
      builder.ifne label
      # get rid of current value
      builder.pop
      builder.new LilaMultiMethod
      # initialize
      builder.dup
      builder.ldc self.name
      builder.ldc arity
      builder.invokespecial LilaMultiMethod, '<init>',
        [Java::void, Java::java.lang.String, Java::int]
      if self.parameter_list.rest
        dup
        builder.ldc true
        builder.invokevirtual LilaMultiMethod, 'setVariadic', 
          [Java::void, Java::boolean] 
      end
      builder.dup
      builder.ldc self.name
      builder.swap
      builder.invokestatic RT, 'setValue', 
        [Java::void, Java::java.lang.String, LilaObject]
      builder.label label
      builder.checkcast LilaMultiMethod
      # specializers 
      builder.ldc required.length    
      builder.anewarray LilaClass
      required.each_with_index { |parameter, index|
        builder.dup           
        builder.ldc index    
        if parameter.type
          parameter.type.compile context, builder
        else
          builder.getstatuc LilaObject, 'lilaClass'
        end
        builder.aastore 
      }
      # create actual function
      function = Function.new(self.name, self.parameter_list, self.expressions)
      function.compile context, builder
      builder.invokevirtual LilaObject, 'getJavaValue', Java::java.lang.Object
      builder.checkcast MethodHandle     
      # add
      builder.invokevirtual LilaMultiMethod, 'addMethod', 
        [Java::void, LilaClass[], MethodHandle]

    end
  end


  class PredicateMethodDefinition < Struct.new \
    :name, :parameter_list, :predicate, :expressions

    def interpret(interpreter)
      # create actual function
      function = interpreter.eval \
        Function.new(self.name, self.parameter_list, self.expressions)
      # evaluate type expressions inside predicate
      self.predicate.resolveTypes { |expression|
        interpreter.eval expression
      }
      # add method to implicit generic function
      pm = RT.getValue self.name
      unless pm.instance_of? LilaPredicateMethod
        pm = LilaPredicateMethod.new name, self.parameter_list.length
        RT.setValue self.name, pm
      end
      pm.addMethodHandle self.predicate, function.javaValue
      pm.dumpMethods
      # create dispatch function

      # compile each expression inside DF conjunctions once
      # parameter types + return type
      sig = [LilaObject] * (self.parameter_list.length + 1)
      pm.compileExpressions { |expression|
        unless pm.getExpressionInfo expression
          puts "Compiling predicate expression: #{expression}"
          method_name = "__exp#{pm.getNextExpressionIdentifier}"
          # temporary function so identifiers are properly resolved
          fn = Function.new nil, self.parameter_list, expression
          fn.close Context.new
          # actually compile expression
          result = interpreter.compiler.compile expression,
            interpreter.context, method_name, sig do |builder|
              builder.areturn
            end

          interpreter.dump result
          clazz = interpreter.load result
          java_sig = sig.map { |c| c.java_class }
          handle = interpreter.loader.findMethod clazz,
            method_name, *java_sig
          pm.setExpressionInfo expression,
            ExpressionInfo.new(clazz.name, method_name, handle)
        end
      }
      # recompile DAG and dispatch method handle
      pm.updateDispatcher

      puts pm
    end
    
    def compile(context, builder)
      # TODO
    end
  end

  class ClassDefinition < Struct.new :name, :superclasses, :properties
    def interpret(interpreter)
      superclasses = self.superclasses.map { |superclass|
        interpreter.eval superclass
      }.to_java LilaClass
      properties = (self.properties || []).to_java :string
      lilaClass = LilaClass.make self.name, superclasses, properties
      RT.setValue self.name, lilaClass
      lilaClass
    end
    
    def compile(context, builder)
      builder.ldc self.name
      # superclasses
      builder.dup
      builder.ldc self.superclasses.length    
      builder.anewarray LilaClass
      self.superclasses.each_with_index { |superclass, index|
        builder.dup           
        builder.ldc index    
        superclass.compile context, builder
        builder.aastore 
      }
      # properties
      properties = (self.properties || [])
      builder.ldc properties.length    
      builder.anewarray Java::java.lang.String
      properties.each_with_index { |property, index|
        builder.dup           
        builder.ldc index    
        builder.ldc property
        builder.aastore 
      }
      builder.invokestatic LilaClass, 'make', 
        [LilaClass, Java::java.lang.String, 
         LilaClass[], Java::java.lang.String[]]
      builder.invokestatic RT, 'setValue', 
        [Java::void, Java::java.lang.String, LilaObject]
    end
  end

  class VariableDefinition < Struct.new :name, :value
    def interpret(interpreter)
      value = interpreter.eval self.value
      puts value
      RT.setValue self.name, value
    end
    
    def compile(context, builder)
      builder.ldc self.name
      self.value.compile context, builder
      builder.invokestatic RT, 'setValue', 
        [Java::void, Java::java.lang.String, LilaObject]
     end
  end


  class Expression < InternalExpression
    def is_true(builder)
      builder.invokevirtual LilaObject, 'isTrue', [Java::boolean]
    end

    def interpret(interpreter)
      puts interpreter.eval(self)
    end

#    def toString
#      "#[#{self.class.name}]"
#    end

    def hashCode
      hash
    end

    def equals(other)
      self == other
    end
  end

  class Value < Expression
    attr_reader :value

    def initialize(value)
      super()
      @value = value
    end

    def hash
      @value.hash
    end

    def ==(other)
      self.class.equal?(other.class) and
        @value == other.value
    end

    alias eql? ==

    def toString
      @value.to_s
    end

    def resolveBindings(env)
      self
    end

    def close(context) end
  end

  class IntegerValue < Value
    def compile(context, builder)
      builder.new LilaInteger
      builder.dup
      builder.ldc_long @value
      builder.invokespecial LilaInteger, '<init>',
        [Java::void, Java::long]
    end
  end

  class StringValue < Value
    def compile(context, builder)
      builder.new LilaString
      builder.dup
      builder.ldc @value
      builder.invokespecial LilaString, '<init>',
        [Java::void, Java::java.lang.String]
    end

    def toString
      @value.inspect
    end
  end

  class BooleanValue < Value
    def compile(context, builder)
      builder.getstatic LilaBoolean,
        (if @value then :TRUE else :FALSE end),
        LilaBoolean
    end
  end

  class Identifier < Expression
    attr_accessor :name

    def initialize(name)
      super()
      @name = name
    end

    def hash
      @name.hash
    end

    def ==(other)
      self.class.equal?(other.class) and
        @name == other.name
    end

    alias eql? ==

    def toString
      @name
    end

    def resolveBindings(env)
      env[@name] || self
    end

    def compile(context, builder)
      if @parameter
        index = @parameter.function.parameter_list.index @parameter
        builder.aload index
      else
        bootstrap = builder.h_invokestatic RT, 'bootstrapValue',
          CallSite, Lookup, Java::java.lang.String, MethodType
        encoded_name = StringNames.toBytecodeName @name
        builder.invokedynamic encoded_name, [LilaObject], bootstrap
      end
    end

    def close(context)
      parameter = context.find_parameter self.name
      if parameter
        @parameter = maybe_close_parameter context, parameter
      end
    end

    def maybe_close_parameter(context, parameter)
      if parameter.function == context.function
        parameter
      else
        parameter = maybe_close_parameter context.parent, parameter
        context.function.add_closed_parameter parameter
      end
    end
  end

  class ParameterList

    attr_reader :parameters, :closed_parameters, :rest

    def initialize(parameters, rest = false)
      @parameters = parameters
      # ordered set
      @rest = rest
      @closed_parameters = []
    end

    # TODO: only structural equivalence, so
    #       @parameters enough for hash and eql? ?

    def hash
      @parameters.hash
    end

    def ==(other)
      self.class.equal?(other.class) and
        @parameters == other.parameters
    end

    alias eql? ==

    def index(parameter)
       @closed_parameters.index(parameter) ||
         (@closed_parameters.length +
           @parameters.index(parameter))
    end

    def length
      @closed_parameters.length + @parameters.length
    end

    def to_s
      # TODO: show closed parameters?
      "(#{@parameters.join(', ')})"
    end
  end

  class Function < Expression
    attr_reader :parameter_list, :body

    def initialize(name, parameter_list, body)
      super()
      @name = name
      @parameter_list = parameter_list
      parameter_list.parameters.each { |parameter|
        parameter.function = self
      }
      @body = body
      @vars = 0
    end

    def hash
      @parameter_list.hash ^ @body.hash
    end

    def ==(other)
      self.class.equal?(other.class) and
        @parameter_list == other.parameter_list and
        @body == other.body
    end

    alias eql? ==

    def resolveBindings(env)
      # TODO: remove parameter names from env?
      @body = @body.resolveBindings env
      self
    end

    def add_closed_parameter(parameter)
      closed_parameter = @parameter_list.closed_parameters.find { |p|
        p.name == parameter.name
      }
      unless closed_parameter
        closed_parameter = ClosedParameter.new parameter
        closed_parameter.function = self
        @parameter_list.closed_parameters << closed_parameter
      end
      closed_parameter
    end

    def compile(context, builder)
      internal_name = Context.new_function_name

      close context

      # define new toplevel method
      param_type = [LilaObject] * @parameter_list.length
      # rest parameter is of type LilaArray
      if @parameter_list.rest
        param_type[-1] = LilaArray
      end

      builder.class_builder.public_static_method internal_name, [],
        LilaObject, *param_type do |method|
          context = Context.new(context)
          context.function = self
          @body.compile context, method
          method.areturn
        end

      # ensure function is registered after class is loaded,
      # so bootstrap (lookup) will succeed
      function_type = [LilaObject] + param_type
      context.register_internal_function internal_name, @name,
        function_type, @parameter_list.rest

      # link function value
      bootstrap = builder.h_invokestatic RT, 'bootstrapFunction',
        CallSite, Lookup, Java::java.lang.String, MethodType
      encoded_name = StringNames.toBytecodeName internal_name
      builder.invokedynamic encoded_name, [LilaFunction], bootstrap

      unless @parameter_list.closed_parameters.empty?
        @parameter_list.closed_parameters.each { |closed_parameter|
          target_parameter = closed_parameter.parameter
          index = target_parameter.function.parameter_list.index(target_parameter)
          builder.aload index
          close_type = [LilaFunction, LilaObject]
          builder.invokevirtual LilaFunction, 'close', close_type
        }
      end
    end

    def close(context)
      unless @closed
        context = Context.new(context)
        context.function = self
        @body.close context
        @closed = true
      end
    end

    def nextVar
      var = @parameter_list.length + @vars
      @vars += 1
      var
    end

    def toString
      "function #{@parameter_list} { #{@body} }"
    end
  end

  class Parameter
    attr_accessor :function
    attr_reader :name, :type

    def initialize(name, type = nil)
      @name = name
      @type = type
    end

    def hash
      @name.hash ^ @type.hash
    end

    def ==(other)
      self.class.equal?(other.class) and
        @name == other.name and
        @type == other.type
    end

    alias eql? ==

    def to_s
      @name + (if @type then ":: #{@type}" else "" end)
    end
  end

  class ClosedParameter < Parameter
    attr_reader :parameter

    def initialize(parameter)
      super parameter.name
      @parameter = parameter
    end
  end

  class Call < Expression
    lilaObject_array = [].to_java(LilaObject).java_class
    attr_reader :expression, :arguments

    def initialize(expression, arguments)
      super()
      @expression = expression
      @arguments = arguments
    end

    def hash
      @expression.hash ^ @arguments.hash
    end

    def ==(other)
      self.class.equal?(other.class) and
        @expression == other.expression and
        @arguments == other.arguments
    end

    alias eql? ==

    def resolveBindings(env)
      @expression = @expression.resolveBindings env
      @arguments = @arguments.resolveBindings env
      self
    end

    def compile(context, builder)
      @expression.compile context, builder
      @arguments.compile context, builder
      bootstrap = builder.h_invokestatic RT, 'bootstrapCall',
        CallSite, Lookup, Java::java.lang.String, MethodType
      # +2: return value, function argument
      type = [LilaObject] * (2 + @arguments.length)
      builder.invokedynamic 'call', type, bootstrap
    end

    def close(context)
      @expression.close context
      @arguments.close context
    end

    def toString
      "#{@expression}#{@arguments}"
    end
  end

  class Arguments
    attr_reader :expressions

    def initialize(expressions)
      @expressions = expressions
    end

    def hash
      @expressions.hash
    end

    def ==(other)
      self.class.equal?(other.class) and
        @expressions == other.expressions
    end

    alias eql? ==

    def length
      @expressions.length
    end

    def resolveBindings(env)
      @expressions = @expressions.map {|expression|
        expression.resolveBindings env
      }
      self
    end

    def compile(context, builder)
      @expressions.each { |argument|
        argument.compile context, builder
      }
    end

    def close(context)
      @expressions.each { |expression|
        expression.close context
      }
    end

    def to_s
      "(#{@expressions.join(', ')})"
    end
  end

  class Conditional < Expression
    attr_reader :test, :consequent, :alternate

    def initialize(test, consequent, alternate)
      super()
      @test = test
      @consequent = consequent
      @alternate = alternate
    end

    def hash
      @test.hash ^
        @consequent.hash ^
        @alternate.hash
    end

    def ==(other)
      self.class.equal?(other.class) and
        @test == other.test and
        @consequent == other.consequent and
        @alternate == other.alternate
    end

    alias eql? ==

    def resolveBindings(env)
      @test = @test.resolveBindings env
      @consequent = @consequent.resolveBindings env
      @alternate = @alternate.resolveBindings env
      self
    end

    def compile(context, builder)
      @test.compile context, builder
      is_true builder
      else_label = gensym
      builder.ifeq else_label
      @consequent.compile context, builder
      end_label = gensym
      builder.goto end_label
      builder.label else_label
      @alternate.compile context, builder
      builder.label end_label
    end

    def close(context)
      [@test, @consequent, @alternate].each { |expression|
        expression.close context
      }
     end

     def toString
       "if #{@test} { #{@consequent} } else { #{@alternate} }"
     end
  end

  class Loop < Expression
    attr_reader :test, :body

    def initialize(test, body)
      super()
      @test = test
      @body = body
    end

    def hash
      @test.hash ^ @body.hash
    end

    def ==(other)
      self.class.equal?(other.class) and
        @test == other.test and
        @body == other.body
    end

    alias eql? ==

    def resolveBindings(env)
      @test = @test.resolveBindings env
      @body = @body.resolveBindings env
      self
    end

    def compile(context, builder)
      test_label = gensym
      builder.label test_label
      @test.compile context, builder
      is_true builder
      end_label = gensym
      builder.ifeq end_label
      @body.compile context, builder
      # discard result
      builder.pop
      builder.goto test_label
      builder.label end_label
      BooleanValue.new(false).compile context, builder
    end

    def close(context)
      [@test, @body].each { |expression|
        expression.close context
      }
     end

     def toString
       "while #{@test} { #{@body} }"
     end
  end

  class Repetition < Expression
    attr_reader :count, :body

    def initialize(count, body)
      super()
      @count = count
      @body = body
    end

    def hash
      @count.hash ^ @body.hash
    end

    def ==(other)
      self.class.equal?(other.class) and
        @count == other.count and
        @body == other.body
    end

    alias eql? ==

    def resolveBindings(env)
      @count = @count.resolveBindings env
      @body = @body.resolveBindings env
      self
    end

    def compile(context, builder)
      var = context.nextVar
      # TODO: improve: don't box and unbox if constant
      @count.compile context, builder
      builder.getfield LilaInteger, 'value', Java::long
      # TODO: improve: var should be long
      builder.l2i
      builder.istore var
      test_label = gensym
      builder.label test_label
      builder.iload var
      end_label = gensym
      builder.ifeq end_label
      @body.compile context, builder
      # discard result
      builder.pop
      builder.iinc var, -1
      builder.goto test_label
      builder.label end_label
      BooleanValue.new(false).compile context, builder
    end

    def close(context)
      [@count, @body].each { |expression|
        expression.close context
      }
     end

     def toString
       "dotimes #{@count} { #{@body} }"
     end
  end

  class Sequence < Expression
    attr_reader :expressions

    def initialize(expressions)
      super()
      @expressions = expressions
    end

    def hash
      @expressions.hash
    end

    def ==(other)
      self.class.equal?(other.class) and
        @expressions == other.expressions
    end

    alias eql? ==

    def resolveBindings(env)
      @expressions = @expressions.map { |expression|
        expression.resolveBindings env
      }
      self
    end

    def compile(context, builder)
      # discard all but last value
      @expressions[0..-2].each { |expression|
        expression.compile context, builder
        builder.pop
      }
      @expressions.last.compile context, builder
    end

    def close(context)
      @expressions.each { |expression|
        expression.close context
      }
    end

    def toString
      if @expressions.length == 1
        @expressions.first.to_s
      else
        "(#{@expressions.join(', ')})"
      end
    end
  end

  class Binding < Struct.new :name, :value; end
end
