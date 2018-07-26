import "lib/capn" =~ [=> text :DeepFrozen]
exports (reader)

object reader as DeepFrozen:
    ""
    method "Import"(root :DeepFrozen):
        ""
        {
            null
            object ::"c++/src/capnp/schema.capnp:CodeGeneratorRequest.RequestedFile.Import" as DeepFrozen {
                ""
                method id() {
                    ""
                    root.getWord(0)
                }

                method name() {
                    ""
                    text.run(root.getPointer(0))
                }

            }
        }

    method CodeGeneratorRequest(root :DeepFrozen):
        ""
        {
            null
            object ::"c++/src/capnp/schema.capnp:CodeGeneratorRequest" as DeepFrozen {
                ""
                method nodes() {
                    ""
                    _accumulateList.run(root.getPointer(0), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader.Node(r)
                        }

                    })
                }

                method requestedFiles() {
                    ""
                    _accumulateList.run(root.getPointer(1), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader.RequestedFile(r)
                        }

                    })
                }

            }
        }

    method RequestedFile(root :DeepFrozen):
        ""
        {
            null
            object ::"c++/src/capnp/schema.capnp:CodeGeneratorRequest.RequestedFile" as DeepFrozen {
                ""
                method id() {
                    ""
                    root.getWord(0)
                }

                method filename() {
                    ""
                    text.run(root.getPointer(0))
                }

                method imports() {
                    ""
                    _accumulateList.run(root.getPointer(1), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader."Import"(r)
                        }

                    })
                }

            }
        }

    method "Method"(root :DeepFrozen):
        ""
        {
            null
            object ::"c++/src/capnp/schema.capnp:Method" as DeepFrozen {
                ""
                method name() {
                    ""
                    text.run(root.getPointer(0))
                }

                method codeOrder() {
                    ""
                    root.getWord(0).and(65535)
                }

                method paramStructType() {
                    ""
                    root.getWord(1)
                }

                method resultStructType() {
                    ""
                    root.getWord(2)
                }

                method annotations() {
                    ""
                    _accumulateList.run(root.getPointer(1), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader.Annotation(r)
                        }

                    })
                }

                method paramBrand() {
                    ""
                    reader.Brand(root.getPointer(2))
                }

                method resultBrand() {
                    ""
                    reader.Brand(root.getPointer(3))
                }

                method implicitParameters() {
                    ""
                    _accumulateList.run(root.getPointer(4), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader.Parameter(r)
                        }

                    })
                }

            }
        }

    method Enumerant(root :DeepFrozen):
        ""
        {
            null
            object ::"c++/src/capnp/schema.capnp:Enumerant" as DeepFrozen {
                ""
                method name() {
                    ""
                    text.run(root.getPointer(0))
                }

                method codeOrder() {
                    ""
                    root.getWord(0).and(65535)
                }

                method annotations() {
                    ""
                    _accumulateList.run(root.getPointer(1), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader.Annotation(r)
                        }

                    })
                }

            }
        }

    method Superclass(root :DeepFrozen):
        ""
        {
            null
            object ::"c++/src/capnp/schema.capnp:Superclass" as DeepFrozen {
                ""
                method id() {
                    ""
                    root.getWord(0)
                }

                method brand() {
                    ""
                    reader.Brand(root.getPointer(0))
                }

            }
        }

    method Field(root :DeepFrozen):
        ""
        {
            def which :Int := root.getWord(1).and(65535)
            object ::"c++/src/capnp/schema.capnp:Field" as DeepFrozen {
                ""
                method name() {
                    ""
                    text.run(root.getPointer(0))
                }

                method codeOrder() {
                    ""
                    root.getWord(0).and(65535)
                }

                method annotations() {
                    ""
                    _accumulateList.run(root.getPointer(1), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader.Annotation(r)
                        }

                    })
                }

                method discriminantValue() {
                    ""
                    root.getWord(0).shiftRight(16).and(65535).xor(65535)
                }

                method slot() {
                    ""
                    {
                        null
                        object ::"c++/src/capnp/schema.capnp:Field.slot" as DeepFrozen {
                            ""
                            method offset() {
                                ""
                                root.getWord(0).shiftRight(32).and(4294967295)
                            }

                            method type() {
                                ""
                                reader.Type(root.getPointer(2))
                            }

                            method defaultValue() {
                                ""
                                reader.Value(root.getPointer(3))
                            }

                            method hadExplicitDefault() {
                                ""
                                _equalizer.sameEver(root.getWord(2).and(1), 1)
                            }

                        }
                    }
                }

                method group() {
                    ""
                    {
                        null
                        object ::"c++/src/capnp/schema.capnp:Field.group" as DeepFrozen {
                            ""
                            method typeId() {
                                ""
                                root.getWord(2)
                            }

                        }
                    }
                }

                method ordinal() {
                    ""
                    {
                        def which :Int := root.getWord(1).shiftRight(16).and(65535)
                        object ::"c++/src/capnp/schema.capnp:Field.ordinal" as DeepFrozen {
                            ""
                            method implicit() {
                                ""
                                null
                            }

                            method explicit() {
                                ""
                                root.getWord(1).shiftRight(32).and(65535)
                            }

                            method _which() {
                                ""
                                which
                            }

                        }
                    }
                }

                method _which() {
                    ""
                    which
                }

            }
        }

    method Binding(root :DeepFrozen):
        ""
        {
            def which :Int := root.getWord(0).and(65535)
            object ::"c++/src/capnp/schema.capnp:Brand.Binding" as DeepFrozen {
                ""
                method unbound() {
                    ""
                    null
                }

                method type() {
                    ""
                    reader.Type(root.getPointer(0))
                }

                method _which() {
                    ""
                    which
                }

            }
        }

    method Type(root :DeepFrozen):
        ""
        {
            def which :Int := root.getWord(0).and(65535)
            object ::"c++/src/capnp/schema.capnp:Type" as DeepFrozen {
                ""
                method void() {
                    ""
                    null
                }

                method bool() {
                    ""
                    null
                }

                method int8() {
                    ""
                    null
                }

                method int16() {
                    ""
                    null
                }

                method int32() {
                    ""
                    null
                }

                method int64() {
                    ""
                    null
                }

                method uint8() {
                    ""
                    null
                }

                method uint16() {
                    ""
                    null
                }

                method uint32() {
                    ""
                    null
                }

                method uint64() {
                    ""
                    null
                }

                method float32() {
                    ""
                    null
                }

                method float64() {
                    ""
                    null
                }

                method text() {
                    ""
                    null
                }

                method data() {
                    ""
                    null
                }

                method list() {
                    ""
                    {
                        null
                        object ::"c++/src/capnp/schema.capnp:Type.list" as DeepFrozen {
                            ""
                            method elementType() {
                                ""
                                reader.Type(root.getPointer(0))
                            }

                        }
                    }
                }

                method enum() {
                    ""
                    {
                        null
                        object ::"c++/src/capnp/schema.capnp:Type.enum" as DeepFrozen {
                            ""
                            method typeId() {
                                ""
                                root.getWord(1)
                            }

                            method brand() {
                                ""
                                reader.Brand(root.getPointer(0))
                            }

                        }
                    }
                }

                method struct() {
                    ""
                    {
                        null
                        object ::"c++/src/capnp/schema.capnp:Type.struct" as DeepFrozen {
                            ""
                            method typeId() {
                                ""
                                root.getWord(1)
                            }

                            method brand() {
                                ""
                                reader.Brand(root.getPointer(0))
                            }

                        }
                    }
                }

                method "interface"() {
                    ""
                    {
                        null
                        object ::"c++/src/capnp/schema.capnp:Type.interface" as DeepFrozen {
                            ""
                            method typeId() {
                                ""
                                root.getWord(1)
                            }

                            method brand() {
                                ""
                                reader.Brand(root.getPointer(0))
                            }

                        }
                    }
                }

                method anyPointer() {
                    ""
                    {
                        def which :Int := root.getWord(0).shiftRight(32).and(65535)
                        object ::"c++/src/capnp/schema.capnp:Type.anyPointer" as DeepFrozen {
                            ""
                            method unconstrained() {
                                ""
                                {
                                    def which :Int := root.getWord(0).shiftRight(16).and(65535)
                                    object ::"c++/src/capnp/schema.capnp:Type.anyPointer.unconstrained" as DeepFrozen {
                                        ""
                                        method anyKind() {
                                            ""
                                            null
                                        }

                                        method struct() {
                                            ""
                                            null
                                        }

                                        method list() {
                                            ""
                                            null
                                        }

                                        method capability() {
                                            ""
                                            null
                                        }

                                        method _which() {
                                            ""
                                            which
                                        }

                                    }
                                }
                            }

                            method parameter() {
                                ""
                                {
                                    null
                                    object ::"c++/src/capnp/schema.capnp:Type.anyPointer.parameter" as DeepFrozen {
                                        ""
                                        method scopeId() {
                                            ""
                                            root.getWord(1)
                                        }

                                        method parameterIndex() {
                                            ""
                                            root.getWord(0).shiftRight(16).and(65535)
                                        }

                                    }
                                }
                            }

                            method implicitMethodParameter() {
                                ""
                                {
                                    null
                                    object ::"c++/src/capnp/schema.capnp:Type.anyPointer.implicitMethodParameter" as DeepFrozen {
                                        ""
                                        method parameterIndex() {
                                            ""
                                            root.getWord(0).shiftRight(16).and(65535)
                                        }

                                    }
                                }
                            }

                            method _which() {
                                ""
                                which
                            }

                        }
                    }
                }

                method _which() {
                    ""
                    which
                }

            }
        }

    method Brand(root :DeepFrozen):
        ""
        {
            null
            object ::"c++/src/capnp/schema.capnp:Brand" as DeepFrozen {
                ""
                method scopes() {
                    ""
                    _accumulateList.run(root.getPointer(0), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader.Scope(r)
                        }

                    })
                }

            }
        }

    method Value(root :DeepFrozen):
        ""
        {
            def which :Int := root.getWord(0).and(65535)
            object ::"c++/src/capnp/schema.capnp:Value" as DeepFrozen {
                ""
                method void() {
                    ""
                    null
                }

                method bool() {
                    ""
                    _equalizer.sameEver(root.getWord(0).shiftRight(16).and(1), 1)
                }

                method int8() {
                    ""
                    root.getWord(0).shiftRight(16).and(255).subtract(256).and(256.negate())
                }

                method int16() {
                    ""
                    root.getWord(0).shiftRight(16).and(65535).subtract(65536).and(65536.negate())
                }

                method int32() {
                    ""
                    root.getWord(0).shiftRight(32).and(4294967295).subtract(4294967296).and(4294967296.negate())
                }

                method int64() {
                    ""
                    root.getWord(1).subtract(18446744073709551616).and(18446744073709551616.negate())
                }

                method uint8() {
                    ""
                    root.getWord(0).shiftRight(16).and(255)
                }

                method uint16() {
                    ""
                    root.getWord(0).shiftRight(16).and(65535)
                }

                method uint32() {
                    ""
                    root.getWord(0).shiftRight(32).and(4294967295)
                }

                method uint64() {
                    ""
                    root.getWord(1)
                }

                method float32() {
                    ""
                    null
                }

                method float64() {
                    ""
                    null
                }

                method text() {
                    ""
                    text.run(root.getPointer(0))
                }

                method data() {
                    ""
                    null
                }

                method list() {
                    ""
                    null
                }

                method enum() {
                    ""
                    root.getWord(0).shiftRight(16).and(65535)
                }

                method struct() {
                    ""
                    null
                }

                method "interface"() {
                    ""
                    null
                }

                method anyPointer() {
                    ""
                    null
                }

                method _which() {
                    ""
                    which
                }

            }
        }

    method NestedNode(root :DeepFrozen):
        ""
        {
            null
            object ::"c++/src/capnp/schema.capnp:Node.NestedNode" as DeepFrozen {
                ""
                method name() {
                    ""
                    text.run(root.getPointer(0))
                }

                method id() {
                    ""
                    root.getWord(0)
                }

            }
        }

    method Annotation(root :DeepFrozen):
        ""
        {
            null
            object ::"c++/src/capnp/schema.capnp:Annotation" as DeepFrozen {
                ""
                method id() {
                    ""
                    root.getWord(0)
                }

                method value() {
                    ""
                    reader.Value(root.getPointer(0))
                }

                method brand() {
                    ""
                    reader.Brand(root.getPointer(1))
                }

            }
        }

    method Parameter(root :DeepFrozen):
        ""
        {
            null
            object ::"c++/src/capnp/schema.capnp:Node.Parameter" as DeepFrozen {
                ""
                method name() {
                    ""
                    text.run(root.getPointer(0))
                }

            }
        }

    method Node(root :DeepFrozen):
        ""
        {
            def which :Int := root.getWord(1).shiftRight(32).and(65535)
            object ::"c++/src/capnp/schema.capnp:Node" as DeepFrozen {
                ""
                method id() {
                    ""
                    root.getWord(0)
                }

                method displayName() {
                    ""
                    text.run(root.getPointer(0))
                }

                method displayNamePrefixLength() {
                    ""
                    root.getWord(1).and(4294967295)
                }

                method scopeId() {
                    ""
                    root.getWord(2)
                }

                method nestedNodes() {
                    ""
                    _accumulateList.run(root.getPointer(1), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader.NestedNode(r)
                        }

                    })
                }

                method annotations() {
                    ""
                    _accumulateList.run(root.getPointer(2), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader.Annotation(r)
                        }

                    })
                }

                method file() {
                    ""
                    null
                }

                method struct() {
                    ""
                    {
                        null
                        object ::"c++/src/capnp/schema.capnp:Node.struct" as DeepFrozen {
                            ""
                            method dataWordCount() {
                                ""
                                root.getWord(1).shiftRight(48).and(65535)
                            }

                            method pointerCount() {
                                ""
                                root.getWord(3).and(65535)
                            }

                            method preferredListEncoding() {
                                ""
                                null
                            }

                            method isGroup() {
                                ""
                                _equalizer.sameEver(root.getWord(3).shiftRight(32).and(1), 1)
                            }

                            method discriminantCount() {
                                ""
                                root.getWord(3).shiftRight(48).and(65535)
                            }

                            method discriminantOffset() {
                                ""
                                root.getWord(4).and(4294967295)
                            }

                            method fields() {
                                ""
                                _accumulateList.run(root.getPointer(3), object _ as null {
                                    "For-loop body"
                                    method run(_, r, _) {
                                        ""
                                        reader.Field(r)
                                    }

                                })
                            }

                        }
                    }
                }

                method enum() {
                    ""
                    {
                        null
                        object ::"c++/src/capnp/schema.capnp:Node.enum" as DeepFrozen {
                            ""
                            method enumerants() {
                                ""
                                _accumulateList.run(root.getPointer(3), object _ as null {
                                    "For-loop body"
                                    method run(_, r, _) {
                                        ""
                                        reader.Enumerant(r)
                                    }

                                })
                            }

                        }
                    }
                }

                method "interface"() {
                    ""
                    {
                        null
                        object ::"c++/src/capnp/schema.capnp:Node.interface" as DeepFrozen {
                            ""
                            method methods() {
                                ""
                                _accumulateList.run(root.getPointer(3), object _ as null {
                                    "For-loop body"
                                    method run(_, r, _) {
                                        ""
                                        reader."Method"(r)
                                    }

                                })
                            }

                            method superclasses() {
                                ""
                                _accumulateList.run(root.getPointer(4), object _ as null {
                                    "For-loop body"
                                    method run(_, r, _) {
                                        ""
                                        reader.Superclass(r)
                                    }

                                })
                            }

                        }
                    }
                }

                method const() {
                    ""
                    {
                        null
                        object ::"c++/src/capnp/schema.capnp:Node.const" as DeepFrozen {
                            ""
                            method type() {
                                ""
                                reader.Type(root.getPointer(3))
                            }

                            method value() {
                                ""
                                reader.Value(root.getPointer(4))
                            }

                        }
                    }
                }

                method annotation() {
                    ""
                    {
                        null
                        object ::"c++/src/capnp/schema.capnp:Node.annotation" as DeepFrozen {
                            ""
                            method type() {
                                ""
                                reader.Type(root.getPointer(3))
                            }

                            method targetsFile() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(48).and(1), 1)
                            }

                            method targetsConst() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(49).and(1), 1)
                            }

                            method targetsEnum() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(50).and(1), 1)
                            }

                            method targetsEnumerant() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(51).and(1), 1)
                            }

                            method targetsStruct() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(52).and(1), 1)
                            }

                            method targetsField() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(53).and(1), 1)
                            }

                            method targetsUnion() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(54).and(1), 1)
                            }

                            method targetsGroup() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(55).and(1), 1)
                            }

                            method targetsInterface() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(56).and(1), 1)
                            }

                            method targetsMethod() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(57).and(1), 1)
                            }

                            method targetsParam() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(58).and(1), 1)
                            }

                            method targetsAnnotation() {
                                ""
                                _equalizer.sameEver(root.getWord(1).shiftRight(59).and(1), 1)
                            }

                        }
                    }
                }

                method parameters() {
                    ""
                    _accumulateList.run(root.getPointer(5), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader.Parameter(r)
                        }

                    })
                }

                method isGeneric() {
                    ""
                    _equalizer.sameEver(root.getWord(4).shiftRight(32).and(1), 1)
                }

                method _which() {
                    ""
                    which
                }

            }
        }

    method Scope(root :DeepFrozen):
        ""
        {
            def which :Int := root.getWord(1).and(65535)
            object ::"c++/src/capnp/schema.capnp:Brand.Scope" as DeepFrozen {
                ""
                method scopeId() {
                    ""
                    root.getWord(0)
                }

                method "bind"() {
                    ""
                    _accumulateList.run(root.getPointer(0), object _ as null {
                        "For-loop body"
                        method run(_, r, _) {
                            ""
                            reader.Binding(r)
                        }

                    })
                }

                method inherit() {
                    ""
                    null
                }

                method _which() {
                    ""
                    which
                }

            }
        }
