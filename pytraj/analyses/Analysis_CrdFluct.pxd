# distutils: language = c++
from pytraj.analyses.Analysis cimport _Analysis, Analysis, RetType
from pytraj.core.DispatchObject cimport _DispatchObject, DispatchObject
from pytraj.core._FunctPtr cimport FunctPtr


cdef extern from "Analysis_CrdFluct.h": 
    cdef cppclass _Analysis_CrdFluct "Analysis_CrdFluct" (_Analysis):
        _Analysis_CrdFluct() 
        _DispatchObject * Alloc() 
        void Help()


cdef class Analysis_CrdFluct (Analysis):
    cdef _Analysis_CrdFluct* thisptr

