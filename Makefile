
uneval: guards.mast deJSONKit.mast elib/serial/deSubgraphKit.mast
	monte eval uneval.mt

deJSONKit.mast: elib-serial

elib-serial: elib-tables \
             elib/serial/deSubgraphKit.mast \
             elib/serial/makeUncaller.mast \
             elib/serial/DEBuilderOf.mast

elib-tables: elib/tables/makeCycleBreaker.mast

%.mast: %.mt
	@ echo "MONTEC $<"
	@ monte bake $<

clean:
	rm -f *.mast elib/*/*.mast
