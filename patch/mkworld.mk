mkworld: mkworld_custom.o mkworld-core.a
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $^

# ONE_OBJS includes the source-available controller and the daemon service.
mkworld-core.a: $(CORE_OBJS)
	$(RM) $@
	$(AR) rcs $@ $^
