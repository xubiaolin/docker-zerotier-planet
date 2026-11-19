mkworld: mkworld_custom.o $(CORE_OBJS) $(ONE_OBJS)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)
