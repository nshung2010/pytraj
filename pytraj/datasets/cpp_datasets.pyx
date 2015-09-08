# distutils: language = c++
from __future__ import division
import operator
from cython.operator cimport preincrement as incr, dereference as deref
from cpython.array cimport array as pyarray
from cython.view cimport array as cyarray

# python level
from pytraj.utils import _import_numpy, _import
from ..utils import is_int
from .._shared_methods import _frame_iter
from .._shared_methods import _xyz, _tolist
from .._shared_methods import my_str_method
from .._cyutils import get_positive_idx
from ..trajs.TrajectoryCpptraj import TrajectoryCpptraj
from ..Topology cimport Topology
from ..externals.six import string_types


cdef class DataSet_1D (DataSet):
    def __cinit__(self, *args):
        cdef DataSet dset
        # make sure two pointers pointing to the same address
        self.baseptr_1 = <_DataSet_1D*> self.baseptr0

    def __dealloc__(self):
        pass

    def __str__(self):
        _, np = _import_numpy()
        basic_str = super(DataSet_1D, self).__str__() + "\n"
        if np:
            my_str = basic_str + "values: \n" + self.values.__str__()
        else:
            my_str = basic_str
        return my_str

    def __repr__(self):
        return self.__str__()

    def __len__(self):
        return self.size

    @property
    def shape(self):
        return (self.size,)

    def _recast_pointers(self, idx=0):
        """
        Since we use >=2 pointers pointing to the same address,
        we need to recast after each pointer assignment
        """
        if idx == 0:
            self.baseptr_1 = <_DataSet_1D*> self.baseptr0
        elif idx == 1:
            self.baseptr0 = <_DataSet*> self.baseptr_1
        else:
            raise ValueError("idx must be 0 or 1")

    def allocate_1D(self, size_t sizet):
        return self.baseptr_1.Allocate1D(sizet)

    def _d_val(self, size_t sizet):
        return self.baseptr_1.Dval(sizet)

    def _xcrd(self, size_t sizet):
        return self.baseptr_1.Xcrd(sizet)

    def _is_torsion_array(self):
        return self.baseptr_1.IsTorsionArray()

    def from_array_like(self, array_like):
        """
        Notes: require numpy
        """
        old_size = self.size
        self.resize(self.size + len(array_like))
        self.values[old_size:] = array_like

    def avg(self):
        return sum(self.values) / len(self)

    def mean(self, *args, **kwd):
        import numpy as np
        return np.mean(self.values, *args, **kwd)

    def mean_with_error(self, DataSet other):
        m0 = self.mean()
        m1 = other.mean() 
        return ((m0 + m1)/2., abs(m0 - m1)/2.)

    def min(self, *args, **kwd):
        return self.baseptr_1.Min()

    def max(self, *args, **kwd):
        return self.baseptr_1.Max()

    def cross_corr(self, DataSet_1D D2, DataSet_1D Ct, int lagmaxIn, 
                bint calccovar, bint usefft):
        return self.baseptr_1.CrossCorr(D2.baseptr_1[0], Ct.baseptr_1[0], 
                lagmaxIn, calccovar, usefft)

    def corr_coeff(self, DataSet_1D other):
        return self.baseptr_1.CorrCoeff(other.baseptr_1[0])

    # below are copied from `dask` package: New BSD
    # see pytraj/licenses/externals/dask.txt for license
    def __abs__(self):
        return elemwise(operator.abs, self)
    def __add__(self, other):
        return elemwise(operator.add, self, other)
    def __radd__(self, other):
        return elemwise(operator.add, other, self)
    def __and__(self, other):
        return elemwise(operator.and_, self, other)
    def __rand__(self, other):
        return elemwise(operator.and_, other, self)
    def __div__(self, other):
        return elemwise(operator.div, self, other)
    def __rdiv__(self, other):
        return elemwise(operator.div, other, self)
    def __invert__(self):
        return elemwise(operator.invert, self)
    def __lshift__(self, other):
        return elemwise(operator.lshift, self, other)
    def __rlshift__(self, other):
        return elemwise(operator.lshift, other, self)
    def __mod__(self, other):
        return elemwise(operator.mod, self, other)
    def __rmod__(self, other):
        return elemwise(operator.mod, other, self)
    def __mul__(self, other):
        return elemwise(operator.mul, self, other)
    def __rmul__(self, other):
        return elemwise(operator.mul, other, self)
    def __neg__(self):
        return elemwise(operator.neg, self)
    def __or__(self, other):
        return elemwise(operator.or_, self, other)
    def __pos__(self):
        return self
    def __ror__(self, other):
        return elemwise(operator.or_, other, self)
    def __rpow__(self, other):
        return elemwise(operator.pow, other, self)
    def __rshift__(self, other):
        return elemwise(operator.rshift, self, other)
    def __rrshift__(self, other):
        return elemwise(operator.rshift, other, self)
    def __sub__(self, other):
        return elemwise(operator.sub, self, other)
    def __rsub__(self, other):
        return elemwise(operator.sub, other, self)
    def __truediv__(self, other):
        return elemwise(operator.truediv, self, other)
    def __rtruediv__(self, other):
        return elemwise(operator.truediv, other, self)
    def __floordiv__(self, other):
        return elemwise(operator.floordiv, self, other)
    def __rfloordiv__(self, other):
        return elemwise(operator.floordiv, other, self)
    def __xor__(self, other):
        return elemwise(operator.xor, self, other)
    def __rxor__(self, other):
        return elemwise(operator.xor, other, self)

    # end of copy from dask

def elemwise(op, self, other=None):
    if other:
        if hasattr(other, 'values'):
            _other = other.values
        else:
            _other = other
        if hasattr(self, 'values'):
            _self = self.values
        else:
            _self = self
        return op(_self, _other)
    else:
        return op(self.values)


cdef class DatasetDouble (DataSet_1D):
    def __cinit__(self, *args):
        # TODO : Use only one pointer? 
        self.baseptr0 = <_DataSet*> new _DatasetDouble()
        # make sure 3 pointers pointing to the same address?
        self.baseptr_1 = <_DataSet_1D*> self.baseptr0
        self.thisptr = <_DatasetDouble*> self.baseptr0

        # let Python/Cython free memory
        self.py_free_mem = True

        if args:
            if isinstance(args[0], list):
                self.data = args[0]

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr


    def alloc(self):
        '''return a memoryview as DataSet instane'''
        cdef DataSet dset = DataSet()
        dset.baseptr0 = self.thisptr.Alloc()
        return dset

    def __getitem__(self, idx):
        #return self.thisptr.index_opr(idx)
        # use self.data so we can use fancy indexing
        return self.data[idx]

    def __setitem__(self, int idx, double value):
        cdef double* ptr
        ptr = &(self.thisptr.index_opr(idx))
        ptr[0] = value
        
    def __iter__(self):
        cdef int i
        for i in range(self.size):
            yield self.thisptr.index_opr(i)

    def add_element(self, double d):
        self.thisptr.AddElement(d)

    def resize(self, size_t sizeIn):
        self.thisptr.Resize(sizeIn)

    def info(self):
        self.thisptr.Info()

    def xcrd(self, size_t idx):
        raise NotImplementedError()

    def append(self, dset, idx=None):
        cdef DatasetDouble dset_
        cdef double elm
        cdef size_t idx_

        if isinstance(dset, DatasetDouble):
            if idx is not None:
                raise ValueError("can not use id with DatasetDouble instance")
            dset_ = dset
            self.thisptr.Append(dset_.thisptr[0])
        else:
            # try to add a `double` elm
            elm = dset
            idx_ = <size_t> idx
            self.thisptr.Add(idx_, <void*> (&elm))

    property data:
        def __get__(self):
            """return memoryview of data array
            """
            cdef cyarray myview
            cdef int size = self.size
            cdef double* ptr

            if size == 0:
                return None
            ptr = &self.thisptr.index_opr(0)
            myview = <double[:size]> ptr
            return myview

        def __set__(self, data):
            cdef vector[double] v
            cdef double x

            for x in data:
                # really need to do this?
                v.push_back(<double> x)
            self.thisptr.assign_opr(v)

cdef class DatasetFloat (DataSet_1D):
    def __cinit__(self):
        self.baseptr0 = <_DataSet*> new _DatasetFloat()
        self.baseptr_1 = <_DataSet_1D*> self.baseptr0
        self.thisptr = <_DatasetFloat*> self.baseptr0

        # let Python/Cython free memory
        self.py_free_mem = True

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr

    def alloc(self):
        '''return a memoryview as DataSet instane'''
        cdef DataSet dset = DataSet()
        dset.baseptr0 = self.thisptr.Alloc()
        return dset

    def __getitem__(self, idx):
        return self.data[idx]

    def __setitem__(self, idx, value):
        self.data[idx] = value
        
    def __iter__(self):
        cdef int i
        for i in range(self.size):
            yield self.thisptr.index_opr(i)

    def resize(self, size_t sizeIn):
        self.thisptr.Resize(sizeIn)

    property data:
        def __get__(self):
            """return memoryview of data array
            """
            cdef cyarray myview
            cdef int size = self.size
            cdef float* ptr

            if size == 0:
                return None
            ptr = &self.thisptr.index_opr(0)
            myview = <float[:size]> ptr
            return myview

        def __set__(self, data):
            raise NotImplementedError()

    def append(self, ds):
        cdef int new_size = self.size + ds.size
        cdef int j
        self.resize(new_size)

        j = 0
        for i in range(self.size, new_size):
            self[i] = ds[j]
            j += 1

cdef class DatasetInteger (DataSet_1D):
    def __cinit__(self):
        # TODO : Use only one pointer? 
        self.baseptr0 = <_DataSet*> new _DatasetInteger()
        # make sure 3 pointers pointing to the same address?
        self.baseptr_1 = <_DataSet_1D*> self.baseptr0
        self.thisptr = <_DatasetInteger*> self.baseptr0

        # let Python/Cython free memory
        self.py_free_mem = True

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr

    def alloc(self):
        '''return a memoryview as DataSet instane'''
        cdef DataSet dset = DataSet()
        dset.baseptr0 = self.thisptr.Alloc()
        return dset

    def __getitem__(self, idx):
        #return self.thisptr.index_opr(idx)
        cdef pyarray arr0 = pyarray('i', [])
        cdef int i

        if is_int(idx):
            return self.thisptr.index_opr(idx)
        elif isinstance(idx, slice):
            if idx == slice(None):
                for i in range(self.size):
                    arr0.append(self.thisptr.index_opr(i))
                return arr0
            else:
                raise NotImplementedError("only support slice(None)")
        else:
            raise NotImplementedError("only support single indexing or slice(None)")

    def __setitem__(self, int idx, int value):
        cdef int * ptr
        ptr = &(self.thisptr.index_opr(idx))
        ptr[0] = value
        
    def __iter__(self):
        cdef int i
        cdef int size = self.size
        for i in range(size):
            yield self.thisptr.index_opr(i)

    def resize(self, size_t sizeIn):
        self.thisptr.Resize(sizeIn)

    def count(self, value=None):
        """
        Parameters
        value : int, optional

        Examples
        --------
        ds.count()
        ds.count(1)
        """
        cdef int i, count

        if value is None:
            from collections import Counter
            return Counter(self.data)
        else:
            count = 0
            for i in self:
                if value == i:
                    count += 1
            return count

    def append(self, values):
        cdef int i, d
        cdef int[:] int_view
        cdef pyarray arr

        if hasattr(values, 'real') and hasattr(values, 'imag'):
            # a number
            self.thisptr.AddElement(<int> values)
        else:
            try:
                int_view = values
            except:
                if hasattr(values, 'data'):
                    try:
                        int_view = values.data
                    except:
                        arr = pyarray('i', values)
                        int_view = arr

            for i in range(int_view.shape[0]):
                self.thisptr.AddElement(int_view[i])

    def _add(self, int idx, int value):
        self.thisptr.Add(idx, &value)

    property data:
        def __get__(self):
            """return memoryview of data array
            """
            cdef cyarray myview
            cdef int size = self.size
            cdef int* ptr

            if size == 0:
                return None
            ptr = &self.thisptr.index_opr(0)
            myview = <int[:size]> ptr
            return myview

        def __set__(self, data):
            cdef vector[int] v
            cdef int x
            cdef size_t size = len(data)

            self.baseptr_1.Allocate1D(size)
            self.data[:] = data


cdef class DatasetString (DataSet_1D):
    def __cinit__(self):
        self.baseptr0 = <_DataSet*> new _DatasetString()
        # make sure 3 pointers pointing to the same address?
        self.baseptr_1 = <_DataSet_1D*> self.baseptr0
        self.thisptr = <_DatasetString*> self.baseptr0

        # let Python/Cython free memory
        self.py_free_mem = True

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr

    def alloc(self):
        '''return a memoryview as DataSet instane'''
        cdef DataSet dset = DataSet()
        dset.baseptr0 = self.thisptr.Alloc()
        return dset

    def __getitem__(self, int idx):
        return self.thisptr.index_opr(idx)

    def __setitem__(self, int idx, value):
        cdef string* ptr
        ptr = &(self.thisptr.index_opr(idx))
        ptr[0] = value
        
    def __iter__(self):
        cdef int i
        for i in range(self.size):
            yield self.thisptr.index_opr(i)

    def resize(self, size_t sizeIn):
        self.thisptr.Resize(sizeIn)

    @property
    def data(self):
        return [s.decode() for s in self]

    def tolist(self):
        return self.data

    def to_pyarray(self):
        cdef pyarray arr0 = pyarray('u', self.tolist())
        return arr0


cdef class DatasetVector (DataSet_1D):
    def __cinit__(self):
        self.py_free_mem = True
        self.thisptr = new _DatasetVector()
        self.baseptr0 = <_DataSet*> self.thisptr
        self.baseptr_1= <_DataSet_1D*> self.thisptr

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr

    @property
    def shape(self):
        return (self.size, 3)

    def alloc(self):
        cdef DataSet d0 = DataSet()
        d0.baseptr0 = self.thisptr.Alloc()
        return d0

    def __getitem__(self, idx):
        """return memoryview for Vec3. No data is copied.
        """
        cdef Vec3 vec = Vec3()
        if idx == -1:
            idx = self.size - 1
        vec.py_free_mem = False
        vec.thisptr = &(self.thisptr.index_opr(idx))
        return vec

    def __iter__(self):
        for i in range (self.size):
            yield self[i]

    def resize(self, size_t sizeIn):
        self.thisptr.Resize(sizeIn)

    def append(self, Vec3 vec):
        self.thisptr.AddVxyz(vec.thisptr[0])

    def from_array_like(self, double[:, :] arr):
        cdef int i
        cdef double[:] xyz
        cdef _Vec3 _vec

        if arr.shape[1] != 3:
            raise ValueError("must have shape = (n_frames, 3))")

        for i in range(arr.shape[0]):
            xyz = arr[i]
            _vec.Assign(&xyz[0])
            self.thisptr.AddVxyz(_vec)

    def tolist(self):
        # overwrite
        # x is memview array
        return [x.tolist() for x in self.data]

    def to_ndarray(self, copy=True):
        # rewrite to make fast copy
        # use `copy=True` as dummy argument to be 
        # consistent with DataSet_1D
        import numpy as np
        cdef int i
        cdef int size = self.size
        cdef _Vec3 _vec3
        #cdef double[:, :] dview = np.empty((size, 3), dtype='f8')
        cdef double[:, :] dview = cyarray(shape=(size, 3), 
                itemsize=sizeof(double), format="d")

        for i in range(size):
            _vec3 = self.thisptr.index_opr(i)
            dview[i, 0] = _vec3.Dptr()[0]
            dview[i, 1] = _vec3.Dptr()[1]
            dview[i, 2] = _vec3.Dptr()[2]
        return np.array(dview)

    def to_dataframe(self):
        from pytraj.utils import _import
        _, pd = _import("pandas")
        if pd:
            return pd.DataFrame(self.to_ndarray(), columns=list('xyz'))

    @property
    def data(self):
        """return self.__iter__
        Not sure what else we should return
        """
        return self.__iter__()

    def is_ired(self):
        return self.thisptr.IsIred()

    def set_ired(self):
        self.thisptr.SetIred()

    @property
    def values(self):
        return self.to_ndarray()

cdef class DataSet_2D (DataSet):
    def __cinit__(self):
        # since DataSet_2D inherits from DataSet, make sure two pointers pointing 
        # to the same address
        self.baseptr_1 = <_DataSet_2D*> self.baseptr0

    def __dealloc__(self):
        pass

    @property
    def n_rows(self):
        return self.baseptr_1.Nrows()

    @property
    def n_cols(self):
        return self.baseptr_1.Ncols()

    def get_element(self, int x, int y):
        return self.baseptr_1.GetElement(x, y)

    def allocate_2D(self, size_t x, size_t y):
        self.baseptr_1.Allocate2D(x, y)

    def allocate_half(self, size_t x):
        self.baseptr_1.AllocateHalf(x)

    def allocate_triangle(self, size_t x):
        self.baseptr_1.AllocateTriangle(x)

    def get_full_matrix(self):
        raise NotImplementedError("must over-write in subclass")

    def to_dataframe(self):
        raise NotImplementedError("must overwrite in subclass")

cdef class DatasetMatrixDouble (DataSet_2D):
    def __cinit__(self):
        self.thisptr = new _DatasetMatrixDouble()
        self.baseptr_1 = <_DataSet_2D*> self.thisptr
        self.baseptr0 = <_DataSet*> self.thisptr

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr

    def __getitem__(self, idx):
        return self.data[idx]

    def __iter__(self):
        for value in self.data:
            yield value

    def alloc(self):
        cdef DataSet dset = DataSet()
        dset.baseptr0 = _DatasetMatrixDouble.Alloc()
        return dset

    @property
    def n_snapshots(self):
        return self.thisptr.Nsnapshots()

    def element(self, size_t x, size_t y):
        return self.thisptr.Element(x, y)

    def add_element(self, double d):
        return self.thisptr.AddElement(d)

    def set_element(self,size_t x, size_t y, double d):
        self.thisptr.SetElement(x, y, d)

    def vect(self):
        return self.thisptr.Vect()

    def allocate_vector(self,size_t vsize):
        self.thisptr.AllocateVector(vsize)

    def store_mass(self, Darray mIn):
        self.thisptr.StoreMass(mIn)

    @property
    def mass(self):
        return self.thisptr.Mass()

    def get_full_matrix(self):
        """return python array with length = n_rows*n_cols"""
        cdef int nr = self.n_rows
        cdef int nc = self.n_cols 
        cdef int i, j
        cdef pyarray arr0 = pyarray('d', [])

        for i in range(nr):
            for j in range(nc):
                arr0.append(self.baseptr_1.GetElement(i, j))
        return arr0

    @property
    def data(self):
        """return 1D python array of matrix' data"""
        return self.to_ndarray()

    def to_ndarray(self, copy=True):
        """use copy=True to be the same as DataSet_1D"""
        import numpy as np
        cdef int n_rows = self.n_rows
        cdef int n_cols = self.n_cols
        cdef double[:, :] dview = np.empty((n_rows, n_cols), dtype='f8')
        cdef int i, j

        for i in range(n_rows):
            for j in range(n_cols):
                dview[i, j] = self.baseptr_1.GetElement(i, j)
        return np.asarray(dview)

    def to_cpptraj_sparse_matrix(self):
        """return 1D numpy array, dtype='f8'
        """
        import numpy as np
        cdef int size = self.size
        cdef double[:] dview = np.empty(size, dtype='f8')

        for i in range(size):
            dview[i] = self.thisptr.index_opr(i)
        return np.asarray(dview)

    def to_half_matrix(self):
        import numpy as np
        hm = np.zeros((self.n_rows, self.n_cols)) 
        mt = self.to_cpptraj_sparse_matrix()

        hm[np.triu_indices(self.n_rows, 1)] = mt[mt !=0]
        return hm

cdef class DatasetMatrixFloat (DataSet_2D):
    def __cinit__(self):
        self.thisptr = new _DatasetMatrixFloat()
        self.baseptr_1 = <_DataSet_2D*> self.thisptr
        self.baseptr0 = <_DataSet*> self.thisptr

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr

    def __getitem__(self, idx):
        return self.data[idx]

    def alloc(self):
        cdef DataSet dset = DataSet()
        dset.baseptr0 = _DatasetMatrixFloat.Alloc()
        return dset

    def get_full_matrix(self):
        """return python array with length = n_rows*n_cols"""
        cdef int nr = self.n_rows
        cdef int nc = self.n_cols 
        cdef int i, j
        cdef pyarray arr0 = pyarray('f', [])

        for i in range(nr):
            for j in range(nc):
                arr0.append(self.baseptr_1.GetElement(i, j))
        return arr0

    @property
    def data(self):
        """return 1D python array of matrix' data"""
        return self.get_full_matrix()

    def to_ndarray(self, copy=True):
        # use copy=True to be consistent with DataSet_1D
        from pytraj.utils import _import_numpy
        _, np = _import_numpy()
        if np:
            arr = np.array(self.get_full_matrix()).reshape(
                             self.n_rows, self.n_cols)
            return arr
        else:
            raise ImportError("require numpy")

    def to_ndarray(self, copy=True):
        """use copy=True to be the same as DataSet_1D"""
        import numpy as np
        cdef int n_rows = self.n_rows
        cdef int n_cols = self.n_cols
        cdef float[:, :] dview = np.empty((n_rows, n_cols), dtype='f4')
        cdef int i, j

        for i in range(n_rows):
            for j in range(n_cols):
                dview[i, j] = self.baseptr_1.GetElement(i, j)
        return np.asarray(dview)

    def to_cpptraj_sparse_matrix(self):
        """return 1D numpy array, dtype='f8'
        """
        import numpy as np
        cdef int size = self.size
        cdef float[:] dview = np.empty(size, dtype='f4')

        for i in range(size):
            dview[i] = self.thisptr.index_opr(i)
        return np.asarray(dview)

    def to_half_matrix(self):
        import numpy as np
        hm = np.zeros((self.n_rows, self.n_cols)) 
        mt = self.to_cpptraj_sparse_matrix()

        hm[np.triu_indices(self.n_rows, 1)] = mt[mt !=0]
        return hm


cdef class DataSet_3D (DataSet):
    def __cinit__(self):
        self.baseptr_1 = <_DataSet_3D*> self.baseptr0

    def __dealloc__(self):
        # since this is ABC, don't __dealloc__ here
        pass

cdef class DatasetGridFloat(DataSet_3D):
    def __cinit__(self):
        self.baseptr0 = <_DataSet*> new _DatasetGridFloat()
        self.baseptr_1 = <_DataSet_3D*> self.baseptr0
        self.thisptr = <_DatasetGridFloat*> self.baseptr0
        self.py_free_mem = True

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr

    def __str__(self):
        _, np = _import_numpy()
        basic_str = super(DataSet_3D, self).__str__() + "\n"
        if np:
            my_str = basic_str + "values: " + self.values.__str__()
        else:
            my_str = basic_str
        return my_str

    def __getitem__(self, idx):
        cdef size_t x, y, z
        x, y, z = idx
        return self.thisptr.GetElement(x, y, z)

    def __setitem__(self, idx, value):
        cdef size_t x, y, z
        x, y, z = idx
        self.thisptr.SetElement(x, y, z, <float> value)

    def resize(self, size_t x, size_t y, size_t z):
        self.thisptr.Allocate3D(x, y, z)

    @property
    def nx(self):
        return self.thisptr.NX()

    @property
    def ny(self):
        return self.thisptr.NY()

    @property
    def nz(self):
        return self.thisptr.NZ()

    @property
    def shape(self):
        return (self.nx, self.ny, self.nz)

    @property
    def data(self):
        """return a copy of 3D array of Grid"""
        cdef size_t nx, ny, nz
        nx, ny, nz = self.nx, self.ny, self.nz
        cdef float* ptr = &self.thisptr.index_opr(0)
        return <float[:nx, :ny, :nz]> ptr

    def to_ndarray(self, copy=True):
        # copy=True: is a dummy argument to be consistent with DataSet_1D
        has_np, np = _import_numpy()
        if not has_np:
            raise ImportError('require numpy')
        else:
            return np.array(self.data[:])

    def tolist(self):
        return [[list(x) for x in y] for y in self.data]
# distutils: language = c++


cdef class DataSet_Modes (DataSet):
    def __cinit__(self):
        self.thisptr = new _DataSet_Modes()
        self.baseptr0 = <_DataSet*> self.thisptr

    def __dealloc__(self):
        del self.thisptr

    def alloc(self):
        '''return a memoryview as DataSet instane'''
        cdef DataSet dset = DataSet()
        dset.baseptr0 = self.thisptr.Alloc()
        return dset


    def nmodes(self):
        return self.thisptr.Nmodes()

    def vector_size(self):
        return self.thisptr.VectorSize()

    def is_reduced(self):
        return self.thisptr.IsReduced()

# distutils: language = c++


cdef class DataSet_RemLog:
    def __cinit__(self):
        self.thisptr = new _DataSet_RemLog()

    def __dealloc__(self):
        del self.thisptr

    #def DataSet_RemLog(self):

    #def DataSet * Alloc(self):

    #def void AllocateReplicas(self,int):

    #def void AddRepFrame(self,int rep, ReplicaFrame frm):

    #def  ReplicaFrame RepFrame(self,int exch, int rep):

    #def int NumExchange(self):

    #def bint ValidEnsemble(self):

    #def void TrimLastExchange(self):

    #def size_t Size(self):

    #def int Sync(self):

    #def void Info(self):

    #def void Add(self,size_t, void *):

cdef class ReplicaFrame:
    def __cinit__(self):
        self.thisptr = new _ReplicaFrame()

    def __dealloc__(self):
        del self.thisptr

cdef class DatasetMatrix3x3 (DataSet_1D):
    def __cinit__(self):
        # TODO : Use only one pointer? 
        self.baseptr0 = <_DataSet*> new _DatasetMatrix3x3()
        # make sure 3 pointers pointing to the same address?
        self.baseptr_1 = <_DataSet_1D*> self.baseptr0
        self.thisptr = <_DatasetMatrix3x3*> self.baseptr0

        # let Python/Cython free memory
        self.py_free_mem = True

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr

    def alloc(self):
        '''return a memoryview as DataSet instane'''
        cdef DataSet dset = DataSet()
        dset.baseptr0 = self.thisptr.Alloc()
        return dset

    def __getitem__(self, int idx):
        if self.size <= 0:
            raise ValueError("size should be > 0")

        cdef Matrix_3x3 mat = Matrix_3x3()
        mat.thisptr[0] = self.thisptr[0][idx]
        return mat

    def __setitem__(self, int idx, double value):
        raise NotImplementedError()
        
    def __iter__(self):
        """return copy"""
        if self.size <= 0:
            raise ValueError("size should be > 0")
        cdef vector[_Matrix_3x3].iterator it = self.thisptr.begin()
        cdef Matrix_3x3 mat

        while it != self.thisptr.end(): 
            mat = Matrix_3x3()
            mat.thisptr[0] = deref(it)
            incr(it)
            yield mat

    def append(self, Matrix_3x3 mat):
        self.thisptr.AddMat3x3(mat.thisptr[0])

    def tolist(self):
        return self.to_ndarray().tolist()

    def to_pyarray(self):
        """slow"""
        return pyarray('d', self.to_ndarray().flatten())

    def to_ndarray(self, copy=True):
        """return a copy
        """
        import numpy as np
        try:
            return np.array([x.to_ndarray(copy=copy) for x in self])
        except ValueError:
            return np.array([], dtype='f8')
        
cdef class DatasetMesh (DataSet_1D):
    def __cinit__(self):
        self.baseptr0 = <_DataSet*> new _DatasetMesh()
        # make sure 3 pointers pointing to the same address?
        self.baseptr_1 = <_DataSet_1D*> self.baseptr0
        self.thisptr = <_DatasetMesh*> self.baseptr0

        # let Python/Cython free memory
        self.py_free_mem = True

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr

    def alloc(self):
        '''return a memoryview as DataSet instane'''
        cdef DataSet dset = DataSet()
        dset.baseptr0 = self.thisptr.Alloc()
        return dset

    def tolist(self):
        """return 2D list with format [index, value]
        """
        # xcrd is for cpptraj's output which use index starting of 1
        # we need to subtract "1"
        return [[int(self._xcrd(i)-1), self._d_val(i)] for i in range(self.size)]

    def to_ndarray(self, copy=True):
        """use copy=True to make consistent with DataSet_1D
        """
        _, np = _import_numpy()
        return np.array(self.tolist())

cdef class DataSet_Coords(DataSet):
    def __cinit__(self):
        # abstract class, dont' create new object here
        #pass
        # make sure that two pointers pointing to the same address
        self.baseptr0 = <_DataSet*> self.baseptr_1
        self._top = Topology()

    def __dealloc__(self):
        # abstract class
        pass

    @property
    def n_frames(self):
        return self.size

    @property
    def n_atoms(self):
        """used for frame_iter"""
        return self.top.n_atoms

    def __str__(self):
        return my_str_method(self)

    def __repr__(self):
        return self.__str__()

    def __call__(self, *args, **kwd):
        return self.frame_iter(*args, **kwd)

    def __iter__(self):
        """iterately getting Frame instance
        TODO : get memoryview or copy?
        """
        cdef int i 
        cdef Frame frame
        frame = self.allocate_frame()

        for i in range(self.size):
            self.baseptr_1.GetFrame(i, frame.thisptr[0])
            yield frame

    def __getitem__(self, idx):
        cdef Frame frame
        frame = self.allocate_frame()
        frame.py_free_mem = True

        if self.size == 0:
            raise ValueError("Your Trajectory is empty, how can I index it?")
        self.baseptr_1.GetFrame(idx, frame.thisptr[0])
        self.tmpfarray = frame
        return self.tmpfarray

    def __setitem__(self, int idx, Frame other):
        idx_1 = get_positive_idx(idx, self.size)
        # raise index out of range
        if idx != 0 and idx_1 == 0:
            # need to check if array has only 1 element. 
            # arr[0] is  arr[-1]
            if idx != -1:
                raise ValueError("index is out of range")
        self.baseptr_1.SetCRD(idx, other.thisptr[0])

    def frame_iter(self, int start=0, int stop=-1, int stride=1, mask=None):
        return _frame_iter(self, start, stop, stride, mask)

    def allocate_frame(self):
        cdef Frame frame = Frame()
        frame.thisptr[0] = self.baseptr_1.AllocateFrame()
        return frame

    property top:
        def __get__(self):
            self._top.thisptr[0] = self.baseptr_1.Top()
            return self._top

        def __set__(self, Topology other):
            self.baseptr_1.SetTopology(other.thisptr[0])

    def add_frame(self, Frame frame):
        self.baseptr_1.AddFrame(frame.thisptr[0])

    def append(self, frame):
        """alis of addframe"""
        self.add_frame(frame)

    def get_frame(self, int idx, Frame frameout):
        self.baseptr_1.GetFrame(idx, frameout.thisptr[0])

    @property
    def xyz(self):
        """return a copy of xyz coordinates (ndarray, shape=(n_frames, n_atoms, 3)
        We can not return a memoryview since Trajectory is a C++ vector of Frame object
        """
        cdef Frame frame
        cdef int i
        _, np = _import_numpy()
        n_frames = self.n_frames 
        n_atoms = self.top.n_atoms
        arr = np.empty((n_frames, n_atoms, 3))

        for i in range(n_frames):
            arr[i] = self[i].xyz
        return arr

    def tolist(self):
        """return flatten list for traj-like object"""
        cdef Frame frame
        return [frame.tolist() for frame in self]

    def to_dataframe(self):
        raise NotImplementedError()

cdef class DataSet_Coords_CRD (DataSet_Coords):
    def __cinit__(self):
        self.thisptr = new _DataSet_Coords_CRD()
        self.baseptr0 = <_DataSet*> self.thisptr
        self.baseptr_1 = <_DataSet_Coords*> self.thisptr

        # let python frees memory
        self.py_free_mem = True

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr

    @classmethod
    def alloc(self):
        cdef DataSet dset = DataSet()
        dset.baseptr0 = _DataSet_Coords_CRD.Alloc()
        return dset

    def load(self, filename_or_traj, top=Topology(), copy_top=False, copy=True):
        cdef Topology tmp_top
        cdef Frame frame

        if isinstance(top, string_types):
            self.top = top = Topology(top)

        if top.is_empty():
            if not self.top.is_empty():
                tmp_top = self.top
            else:
                raise ValueError("need to have non-empty topology file")
        else:
            tmp_top = top
            # update self.top too
            if copy_top == True:
                self.top = top.copy()
            else:
                self.top = top

        if isinstance(filename_or_traj, string_types):
            trajin_single = TrajectoryCpptraj()
            trajin_single.load(filename_or_traj, tmp_top)
            for frame in trajin_single:
                self.append(frame.copy()) # always copy
        else:
            # assume that we can iterate over filename_or_traj to get Frame object
            for frame in filename_or_traj:
                if copy:
                    self.append(frame.copy())
                else:
                    self.append(frame)
# distutils: language = c++


cdef class DataSet_Coords_REF (DataSet_Coords):
    def __cinit__(self):
        self.thisptr = new _DataSet_Coords_REF()
        self.baseptr0 = <_DataSet*> self.thisptr
        self.baseptr_1 = <_DataSet_Coords*> self.thisptr

        # let python frees memory
        self.py_free_mem = True

    def __dealloc__(self):
        if self.py_free_mem:
            del self.thisptr

    @classmethod
    def alloc(self):
        cdef DataSet dset = DataSet()
        dset.baseptr0 = _DataSet_Coords_REF.Alloc()
        return dset

    #@property
    #def size(self):
    #    return self.thisptr.Size()

    def get_frame(self):
        cdef Frame frame = Frame()
        frame.thisptr[0] = self.thisptr.RefFrame()
        return frame

    @property
    def values(self):
        """"""
        return self[0].to_ndarray()

    @property
    def data(self):
        """"""
        return self.values
