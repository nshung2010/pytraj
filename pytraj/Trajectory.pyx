#print print  distutils: language = c++
from __future__ import absolute_import
cimport cython
from cpython.array cimport array as pyarray
from cython.operator cimport dereference as deref
from cython.operator cimport preincrement as incr
from cython.parallel cimport prange
from libc.string cimport memcpy
from .Topology cimport Topology
from .AtomMask cimport AtomMask
from ._utils cimport get_positive_idx
from .TrajinList cimport TrajinList
from .Frame cimport Frame
from .trajs.Trajin cimport Trajin

# python level
from .trajs.Trajin_Single import Trajin_Single
from .externals.six import string_types
from .TrajectoryIterator import TrajectoryIterator
from .utils.check_and_assert import _import_numpy, is_int, is_frame_iter
from .utils.check_and_assert import file_exist, is_mdtraj, is_pytraj_trajectory
from .utils.check_and_assert import is_word_in_class_name
from .utils.check_and_assert import is_array, is_range
from .trajs.Trajout import Trajout
from ._get_common_objects import _get_top, _get_data_from_dtype
from ._shared_methods import _savetraj, _get_temperature_set
from ._shared_methods import _xyz, _tolist
from ._shared_methods import my_str_method
from ._shared_methods import _frame_iter
from ._shared_methods import _box_to_ndarray

import pytraj.common_actions as pyca
from pytraj.hbonds import search_hbonds

cdef class Trajectory (object):
    def __cinit__(self, filename=None, top=None, indices=None, 
                  bint warning=False, n_frames=None, flag=None, check_top=True):
        
        cdef Frame frame

        if check_top:
            self.top = _get_top(filename, top)
            if self.top is None:
                self.top = Topology()
        else:
            self.top = Topology()

        if n_frames is not None:
            # reserve n_frames
            self.resize(n_frames)

        self.oldtop = None
        self.warning = warning

        # since we are using memoryview for slicing this class istance, we just need to 
        # let `parent` free memory
        # this variable is intended to let Trajectory control 
        # freeing memory for Frame instance but it's too complicated
        #self.is_mem_parent = True
        if filename is not None:
            self.load(filename, self.top, indices)

    def copy(self):
        "Return a copy of Trajectory"
        cdef Trajectory other = Trajectory()
        cdef _Frame* _frame_ptr

        other.top = self.top.copy()

        for frame in self:
            other.append(frame, copy=True)
        return other

    def __dealloc__(self):
        """should we free memory for Frame instances here?
        (we set frame.py_free_mem = False in __getitem__)
        """
        #print "Test Trajectory exiting"
        pass
        #cdef Frame frame
        #if self.is_mem_parent:
        #    for frame in self:
        #        # we don't __dealloc__ here.
        #        # just turn py_free_mem on to let Frame class frees memory
        #        # work?
        #        # NO : Error in `python': double free or corruption (out)`
        #        # --> don't need this method. We still have the commented code here to 
        #        # remind not need to add in future.
        #        #frame.py_free_mem = True
        #        del frame.thisptr

    def __del__(self):
        cdef Frame frame
        for frame in self:
            del frame.thisptr

    def __call__(self, *args, **kwd):
        return self.frame_iter(*args, **kwd)

    def load(self, filename='', Topology top=None, indices=None):
        # TODO : add more test cases
        # should we add hdf5 format here?
        #cdef Trajin_Single ts
        cdef int idx
        cdef TrajinList tlist
        cdef Frame frame
        cdef Trajin trajin

        if top is not None:
            if self.top.is_empty():
                self.top = top.copy()
            else:
                pass
            # don't update top if not self.top.is_empty()
        else:
            if self.top.is_empty():
                # if both top and self.top are empty, need to raise ValueError
                try:
                    tmpobj = filename
                    if hasattr(tmpobj, 'top'):
                        self.top = tmpobj.top.copy()
                    elif hasattr(tmpobj[0], 'top'):
                        self.top = tmpobj[0].top.copy()
                except:
                    raise ValueError("need to have non-empty Topology")

        # always use self.top
        if isinstance(filename, string_types):
            # load from single filename
            # we don't use UTF-8 here since ts.load(filename) does this job
            #filename = filename.encode("UTF-8")
            ts = Trajin_Single()
            ts.top = self.top.copy()
            ts.load(filename)
            if indices is None:
                # load all frames
                self.join(ts[:])
            elif isinstance(indices, slice):
                self.join(ts[indices])
            else:
                # indices is tuple, list, ...
                # we loop all traj frames and extract frame-ith in indices 
                # TODO : check negative indexing?
                # increase size of vector
                for idx in indices:
                    self.append(ts[idx], copy=True) # copy=True because we load from disk
        elif isinstance(filename, Frame):
            self.append(filename)
        elif isinstance(filename, (list, tuple)):
            # load from a list/tuple of filenames
            # or a list/tuple of numbers
            _f0 = filename[0]
            if isinstance(_f0, string_types) or hasattr(_f0, 'n_frames'):
                # need to check `string_types` since we need to load list of numbers too.
                # list of filenames
                list_of_files_or_trajs = filename
                for fh in list_of_files_or_trajs:
                    if self.warning:
                        print ("Loading from list/tuple. Ignore `indices`")
                    # recursive
                    self.load(fh, self.top, indices)
            else:
                # load xyz
                try:
                    _xyz = filename
                    self.append_xyz(_xyz)
                except:
                    raise ValueError("must be a list/tuple of either filenames/Traj/numbers")
        elif isinstance(filename, TrajinList):
            # load from TrajinList
            if indices is not None:
                if self.warning:
                    print ("Loading from TrajinList. Ignore `indices`")
            tlist = <TrajinList> filename
            for trajin in tlist:
                trajin.top = tlist.top
                for frame in trajin:
                    self.append(frame)
        elif hasattr(filename, 'n_frames') and not is_mdtraj(filename):
            # load from Traj-like object
            # make temp traj to remind about traj-like
            traj = filename
            if indices is None:
                for frame in traj:
                    self.append(frame)
            else:
                for idx, frame in enumerate(traj):
                    # slow method.
                    if idx in indices:
                        self.append(frame)
        elif is_frame_iter(filename):
            # load from frame_iter
            _frame_iter = filename
            for frame in _frame_iter:
                self.append(frame)
        elif is_mdtraj(filename):
            _traj = filename
            # add "10 *" since mdtraj use 'nm' while pytraj use 'Angstrom'
            self.append_ndarray(10 * _traj.xyz)
        elif is_word_in_class_name(filename, 'DataSetList'):
            # load DataSetList
            # iterate all datasets and get anything having frame_iter
            dslist = filename
            for _d0 in dslist:
                if hasattr(_d0, 'frame_iter'):
                    _d0.top = self.top.copy()
                    # don't let _d0 free memory since we use Topology 'view'
                    for frame in _d0.frame_iter():
                        self.append(frame)
        else:
            try:
                # load from array
                _xyz = filename
                self.append_xyz(_xyz)
            except:
                raise ValueError("filename must be str, traj-like or numpy array")

    @cython.infer_types(True)
    @cython.cdivision(True)
    def append_xyz(self, xyz_in):
        cdef int n_atoms = self.top.n_atoms
        cdef int natom3 = n_atoms * 3
        cdef int n_frames, i 
        """Try loading xyz data with 
        shape=(n_frames, n_atoms, 3) or (n_frames, n_atoms*3) or 1D array

        If using numpy array with shape (n_frames, n_atoms, 3),
        try "append_ndarray" method
        """

        if n_atoms == 0:
            raise ValueError("n_atoms = 0: need to set Topology or use `append_ndarray`'")

        has_np, np = _import_numpy()
        if has_np:
            xyz = np.asarray(xyz_in)
            if len(xyz.shape) == 1:
                n_frames = int(xyz.shape[0]/natom3)
                _xyz = xyz.reshape(n_frames, natom3) 
            elif len(xyz.shape) in [2, 3]:
                _xyz = xyz
            else:
                raise NotImplementedError("only support array/list/tuples with ndim=1,2,3")
            for arr0 in _xyz:
                frame = Frame(n_atoms)
                # flatten either 1D or 2D array
                frame.set_from_crd(arr0.flatten())
                self.append(frame)
        else:
            if isinstance(xyz_in, (list, tuple)):
                xyz_len = len(xyz_in)
                if xyz_len % (natom3) != 0:
                    raise ValueError("Len of list must be n_frames*n_atoms*3")
                else:
                    n_frames = int(xyz_len / natom3)
                    for i in range(n_frames):
                        frame = Frame(n_atoms)
                        frame.set_from_crd(xyz_in[natom3 * i : natom3 * (i + 1)])
                        self.append(frame)
            elif hasattr(xyz_in, 'memview'):
                    frame = Frame(n_atoms)
                    for i in range(xyz_in.shape[0]):
                        frame.append_xyz(xyz_in[i]) 
                        self.append(frame)
            else:
                raise NotImplementedError("must have numpy or list/tuple must be 1D")

    def append_ndarray(self, xyz):
        """load ndarray with shape=(n_frames, n_atoms, 3)"""
        cdef Frame frame
        cdef int i
        cdef double[:, :] myview
        cdef int n_frames = xyz.shape[0]
        cdef int n_atoms = xyz.shape[1]
        cdef int oldsize = self.frame_v.size()
        cdef int newsize = oldsize + n_frames
        import numpy as np

        # need to use double precision
        _xyz = xyz.astype(np.float64)
        self.frame_v.resize(newsize)

        for i in range(n_frames):
            # make memoryview for ndarray
            myview = _xyz[i]
            # since we use `vector[Frame*]`, we need to allocate Frame's size
            self[i + oldsize] = Frame(n_atoms)
            frame = self[i + oldsize]
            # copy coords
            frame[:] = myview[:]

    @property
    def shape(self):
        return (self.n_frames, self[0].n_atoms, 3)

    @property
    def xyz(self):
        """return a copy of xyz coordinates (ndarray, shape=(n_frames, n_atoms, 3)
        We can not return a memoryview since Trajectory is a C++ vector of Frame object
        """
        cdef bint has_numpy
        has_numpy, np = _import_numpy()
        cdef int i
        cdef int n_frames = self.n_frames
        cdef int n_atoms = self.n_atoms
        cdef Frame frame
        myview = np.empty((n_frames, n_atoms, 3))

        if self.n_atoms == 0:
            raise NotImplementedError("need to have non-empty Topology")
        if has_numpy:
            for i, frame in enumerate(self):
                myview[i] = np.asarray(frame.buffer2d[:])
            return np.asarray(myview)
        else:
            raise NotImplementedError("must have numpy")

    def update_xyz(self, xyz):
        # make sure to use double precision for xyz
        cdef int idx, n_frames
        cdef double[:, :, :] xyz_view

        if xyz.shape != self.shape:
            raise ValueError("shape mismatch")

        n_frames = <int> xyz.shape[0]

        _, np = _import_numpy()
        if xyz.dtype != np.float64:
            xyz_view = xyz.astype(np.float64) 
        else:
            xyz_view = xyz

        for idx in range(n_frames):
            # copy
            self[idx, :] = xyz_view[idx, :]

    def _update_xyz_memcpy(self, double[:, :, :] xyz):
        # make sure to use double precision for xyz
        cdef int idx, n_frames
        cdef double* ptr_src
        cdef double* ptr_dest
        cdef size_t count

        n_frames = xyz.shape[0]
        n_atoms = xyz.shape[1]
        count = sizeof(double) * n_atoms * 3

        for idx in range(n_frames):
            ptr_dest = self.frame_v[idx].xAddress()
            ptr_src = &(xyz[idx, 0, 0])
            memcpy(<void*> ptr_dest, <void*> ptr_src, count)

    def _update_xyz_memcpy_openmp(self, double[:, :, :] xyz):
        # make sure to use double precision for xyz
        cdef int idx, n_frames
        cdef double* ptr_src
        cdef double* ptr_dest
        cdef size_t count

        n_frames = xyz.shape[0]
        n_atoms = xyz.shape[1]
        count = sizeof(double) * n_atoms * 3

        for idx in prange(n_frames, nogil=True):
            ptr_dest = self.frame_v[idx].xAddress()
            ptr_src = &(xyz[idx, 0, 0])
            memcpy(<void*> ptr_dest, <void*> ptr_src, count)

    def tolist(self):
        return _tolist(self)

    @cython.boundscheck(False)
    @cython.wraparound(False)
    def __getitem__(self, idxs):
        # TODO : same as Trajin class
        # should combine or inherit or ?
        #"""Return a reference of Trajectory[idx]
        #To get a copy
        #>>>frame = Trajectory_instance[10].copy()

        # TODO : why not using existing slice of list?

        cdef Frame frame = Frame(self.top.n_atoms) # need to allocate here?
        cdef Frame _frame # used for AtomMask selection. will allocate mem later
        cdef Trajectory farray
        cdef int start, stop, step, count
        cdef int i
        cdef int idx_1, idx_2
        cdef int[:] int_view
        cdef AtomMask atom_mask_obj
        cdef pyarray list_arr
        #cdef list tmplist

        # test memoryview for traj[:, :, :]
        cdef double[:, :, :] arr3d

        frame.py_free_mem = False

        if self.warning:
            print "return a Frame or sub-Trajectory view of this instance"
            print "Use with care. For safetype, use `copy` method"

        if len(self) == 0:
            raise ValueError("Your Trajectory is empty, how can I index it?")

        elif isinstance(idxs, AtomMask):
            atom_mask_obj = <AtomMask> idxs
            _farray = Trajectory(check_top=False) # just create naked Trajectory
            _farray.top = self.top._modify_state_by_mask(atom_mask_obj)
            for i, frame in enumerate(self):
                _frame = Frame(frame, atom_mask_obj) # 1st copy
                _frame.py_free_mem = False #
                _farray.append(_frame, copy=False) # 2nd copy if using `copy=True`
            #self.tmpfarray = _farray # why need this?
            # hold _farray in self.tmpfarray to avoid memory lost
            #return self.tmpfarray
            return _farray

        elif isinstance(idxs, string_types):
            # mimic API of MDtraj
            if idxs == 'coordinates':
                return self[:, :, :]
            elif idxs == 'topology':
                return self.top
            else:
                # return array with given mask
                # traj[':@CA']
                # traj[':@CA :frame']
                # use `mask` to avoid confusion
                mask = idxs
                try:
                    atom_mask_obj = self.top(mask)
                    return self[atom_mask_obj]
                except:
                    txt = "not supported keyword `%s` or there's proble with your topology" % idxs
                    raise NotImplementedError(txt)

        elif not isinstance(idxs, slice):
            if isinstance(idxs, tuple):
                idx_0 = idxs[0]

                all_are_slice_instances = True
                for tmp in idxs:
                    if not isinstance(tmp, slice): all_are_slice_instances = False

                has_numpy, _np = _import_numpy()
                # got Segmentation fault if using "is_instance3 and not has_numpy"
                # TODO : Why?
                #if is_instance3 and not has_numpy:
                # TODO : make memoryview for traj[:, :, :]
                if all_are_slice_instances:
                    # return 3D array or list of 2D arrays?
                    # traj[:, :, :]
                    # traj[1:2, :, :]
                    tmplist = []
                    for frame in self[idxs[0]]:
                        tmplist.append(frame[idxs[1:]])
                    if has_numpy:
                        # test memoryview, does not work yet.
                        # don't delete those line to remind we DID work on this
                        #arr3d = _np.empty(shape=_np.asarray(tmplist).shape)
                        #for i, frame in enumerate(self[idxs[0]]):
                        #    for j, f0 in enumerate(frame[idxs[1]]):
                        #        arr3d[i][j] = f0[:]
                        #return arr3d

                        return _np.asarray(tmplist)
                    else:
                        return tmplist

                if isinstance(self[idx_0], Frame):
                    frame = self[idx_0]
                    frame.py_free_mem = False
                    return frame[idxs[1:]]
                elif isinstance(self[idx_0], Trajectory):
                    farray = self[idx_0]
                    return farray[idxs[1:]]
                #return frame[idxs[1:]]
            elif is_array(idxs) or isinstance(idxs, list) or is_range(idxs):
                _farray = self.__class__()
                _farray.top = self.top
                for i in idxs:
                    _farray.append(self[i], copy=False)
                return _farray
            else:
                idx_1 = get_positive_idx(idxs, self.size)
                # raise index out of range
                if idxs != 0 and idx_1 == 0:
                    # need to check if array has only 1 element. 
                    # arr[0] is  arr[-1]
                    if idxs != -1:
                        raise ValueError("index is out of range")
                #print ("get memoryview")
                #frame.thisptr = &(self.frame_v[idx_1])
                frame.py_free_mem = False
                frame.thisptr = self.frame_v[idx_1]
                return frame
        else:
            # is slice
            # creat a subset array of `Trajectory`
            farray = Trajectory()
            # farray.is_mem_parent = False

            # should we make a copy of self.top or get memview?
            farray.top = self.top
            farray.top.py_free_mem = False # let `master` Trajectory do freeing mem
            # create positive indexing for start, stop if they are None
            start, stop, step  = idxs.indices(self.size)
            
            # mimic negative step in python list
            # debug
            #print "before updating (start, stop, step) = (%s, %s, %s)" % (start, stop, step)
            if start > stop and (step < 0):
                # since reading TRAJ is not random access for large file, we read from
                # begining to the end and append Frame to Trajectory
                # we will reverse later after getting all needed frames
                # traj[:-1:-3]
                is_reversed = True
                # swap start and stop but adding +1 (Python does not take last index)
                # a = range(10) # a[5:1:-1] = [5, 4, 3, 2]
                # a[2:5:1] = [2, 3, 4, 5]
                start, stop = stop + 1, start + 1
                step *= -1
            else:
                is_reversed = False

            # debug
            #print "after updating (start, stop, step) = (%s, %s, %s)" % (start, stop, step)
      
            i = start
            while i < stop:
                # turn `copy` to `False` to have memoryview
                # turn `copy` to `True` to make a copy
                farray.append(self[i], copy=False)
                i += step
            if is_reversed:
                # reverse vector if using negative index slice
                # traj[:-1:-3]
                farray.reverse()

            # hold farray by self.tmpfarray object
            # so self[:][0][0] is still legit (but do we really need this with much extra memory?)
            #self.tmpfarray = farray
            #if self.tmpfarray.size == 1:
            #    return self.tmpfarray[0]
            #return self.tmpfarray
            return farray

    def _fast_slice(self, slice my_slice):
        cdef int start, stop, step
        cdef int count
        cdef Trajectory myview = Trajectory(check_top=False)
        cdef _Frame* _frame_ptr

        myview.top = self.top

        start, stop, step  = my_slice.indices(self.size)
        count = start
        while count < stop:
            _frame_ptr = self.frame_v[count]
            myview.frame_v.push_back(_frame_ptr)
            count += step

        return myview

    def __setitem__(self, idx, other):
        # TODO : add slice
        # make a copy
        # to make thing simple, we don't use fancy slicing here
        cdef Frame frame
        if len(self) == 0:
            raise ValueError("Your Trajectory is empty, how can I index it?")
        if isinstance(idx, (long, int)) and isinstance(other, Frame):
            frame = <Frame> other.copy()
            frame.py_free_mem = False
            self.frame_v[idx] = frame.thisptr
        # TODO : check this
        #self[idx].py_free_mem = False
        else:
            # example: self[0, 0, 0] = 100.
            self[idx[0]][idx[1:]] = other
            #txt = "not yet implemented. Try using framearray[idx1][idx2, idx3] = value"
            #raise NotImplementedError(txt)
        
    def __delitem__(self, int idx):
        self.erase(idx)

    def __str__(self):
        return my_str_method(self)

    def __repr__(self):
        return self.__str__()
    
    def __enter__(self):
        return self

    def __exit__(self, *args):
        # we don't do anythin here. Just create the same API for TrajectoryIterator
        pass

    def frame_iter(self, int start=0, int stop=-1, int stride=1, mask=None):
        """iterately get Frames with start, stop, stride 
        Parameters
        ---------
        start : int (default = 0)
        chunk : int (default = 1)
        stop : int (default = max_frames - 1)
        """
        return _frame_iter(self, start, stop, stride, mask)

    def reverse(self):
        # should we just create a fake operator?
        cpp_reverse(self.frame_v.begin(), self.frame_v.end())

    def erase(self, idxs):
        cdef int idx
        # dealloc frame pointer too?
        if is_int(idxs):
            idx = idxs
            self.frame_v.erase(self.frame_v.begin() + idx)
        else:
            # assume : list, slice, iteratable object
            for idx in idxs:
                self.erase(idx)
        
    @property
    def size(self):
        return self.frame_v.size()

    def is_empty(self):
        return self.size == 0

    @property
    def n_frames(self):
        """same as self.size"""
        return self.size

    @property
    def n_atoms(self):
        return self.top.n_atoms

    def __len__(self):
        return self.size

    def __iter__(self):
        """return a reference of Frame instance
        >>> for frame in Trajectory_instance:
        >>>     pass
                
        """
        cdef vector[_Frame*].iterator it  = self.frame_v.begin()
        cdef Frame frame 

        while it != self.frame_v.end():
            frame = Frame()
            # use memoryview, don't let python free memory of this instance
            frame.py_free_mem = False
            #frame.thisptr = &(deref(it))
            frame.thisptr = deref(it)
            yield frame
            incr(it)

    def __add__(self, Trajectory other):
        self += other
        return self

    def __iadd__(self, Trajectory other):
        """
        append `other`'s frames to `self`

        Examples
        -------
        farray += other_farray

        Notes
        -----
        No copy is made (except traj += traj (itself))
        """
        cdef _Frame* _frame_ptr
        cdef _Frame _frame
        cdef Frame frame
        cdef int old_size = self.size
        cdef int i

        if self.top.n_atoms != other.top.n_atoms:
            raise ValueError("n_atoms of two arrays do not match")

        if other is self:
            # why doing this? save memory
            # traj += traj.copy() is too expensive since we need to make a copy first 
            print ("making copies of Frames and append")
            for i in range(old_size):
                self.append(self[i], copy=True)
        else:
            for _frame_ptr in other.frame_v:
                self.frame_v.push_back(_frame_ptr)
        return self

    def append(self, Frame framein, copy=True):
        """append new Frame

        Parameters
        ---------
        framein : Frame object
        copy : bool, default=True
            if 'True', make a copy of Frame. If 'False', create a view
        """
        cdef Frame frame
        # Note: always use `copy=True`
        # use `copy = False` if you want to get memoryview for `self`
        # need to set `py_free_mem = False`
        if copy:
            frame = Frame(framein)
            frame.py_free_mem = False
            self.frame_v.push_back(frame.thisptr)
        else:
            framein.py_free_mem = False
            self.frame_v.push_back(framein.thisptr)

    def join(self, traj, copy=True):
        """traj.join(traj2) with/without copy
        """
        cdef Trajectory other, farray
        cdef Frame frame
        # TODO : do we need this method when we have `get_frames`
        if traj is self:
            raise ValueError("why do you join your self?")
        if is_pytraj_trajectory(traj):
            if self.top.n_atoms != traj.top.n_atoms:
                raise ValueError("n_atoms of two arrays do not match")
            for frame in traj:
                self.append(frame, copy=copy)
        elif isinstance(traj, (list, tuple)):
            # assume a list or tuple of Trajectory
            for farray in traj:
                self.join(farray, copy=copy)

    def resize(self, int n_frames):
        self.frame_v.resize(n_frames)

    @property
    def temperatures(self):
        """return a Python array of temperatures
        """
        cdef pyarray tarr = pyarray('d', [])

        for frame in self:
            tarr.append(frame.temperature)
        return tarr

    @property
    def temperature_set(self):
        return _get_temperature_set(self)

    def get_frames(self, from_traj=None, indices=None, update_top=False, copy=False):
        """get frames from Trajin instance
        def get_frames(from_traj=None, indices=None, update_top=False, copy=True)
        Parameters:
        ----------
        from_traj : TrajectoryIterator or Trajectory, default=None
            if `from_traj` is None, return a new Trajectory (view or copy)
        indices : default=None
        update_top : bool, default=False
        copy : bool, default=True

        Note:
        ----
        Have not support indices yet. Get max_frames from trajetory
        """
        
        cdef int i
        cdef int start, stop, step
        cdef Frame frame

        msg = """Trajectory.top.n_atoms should be equal to Trajin_Single.top.n_atoms 
               or set update_top=True"""

        if from_traj is not None:
            ts = from_traj
            # append new frames to `self`
            if update_top:
                self.top = ts.top.copy()

            if not update_top:
                if self.top.n_atoms != ts.top.n_atoms:
                    raise ValueError(msg)

            if isinstance(ts, Trajin_Single) or isinstance(ts, TrajectoryIterator):
                # alway make a copy
                if indices is not None:
                    # slow method
                    # TODO : use `for idx in leng(indices)`?
                    if isinstance(indices, slice):
                        # use slice for saving memory
                        start, stop, step = indices.start, indices.stop, indices.step
                        for i in range(start, stop, step):
                            self.append(ts[i], copy=True)
                    else:
                        # regular list, tuple, array,...
                        for i in indices:
                            #print "debug Trajectory.get_frames"
                            self.append(ts[i], copy=True)
                else:    
                    # get whole traj
                    frame = Frame()
                    #frame.set_frame_v(ts.top, ts.has_vel(), ts.n_repdims)
                    frame.set_frame_v(ts.top)
                    ts._begin_traj()
                    for i in range(ts.max_frames):
                        ts._get_next_frame(frame)
                        self.append(frame)
                    ts._end_traj()

            elif isinstance(ts, Trajectory):
                # can return a copy or no-copy based on `copy` value
                # use try and except?
                if indices is None:
                    for i in range(ts.size):
                        # TODO : make indices as an array?
                        # create `view`
                        self.append(ts[i], copy=copy)
                else:
                    for i in indices:
                        # TODO : make indices as an array?
                        self.append(ts[i], copy=copy)

        else:
            # if from_traj is None, return new Trajectory
            newfarray = Trajectory()
            if update_top:
                newfarray.top = self.top.copy()
            for i in indices:
                newfarray.append(self[i], copy=copy)
            return newfarray

    def strip_atoms(self, mask=None, update_top=True, bint has_box=False):
        """if you use memory for numpy, you need to update after resizing Frame
        >>> arr0 = np.asarray(frame.buffer)
        >>> frame.strip_atoms(top,"!@CA")
        >>> # update view
        >>> arr0 = np.asarray(frame.buffer)
        """
        cdef AtomMask atm = self.top(mask)
        # read note about `_strip_atoms`
        atm.invert_mask()

        cdef vector[_Frame*].iterator it
        cdef Frame frame = Frame()
        cdef Topology tmptop = Topology()

        if mask == None: 
            raise ValueError("Must provide mask to strip")
        mask = mask.encode("UTF-8")

        # do not dealloc since we use memoryview for _Frame
        frame.py_free_mem = False
        it = self.frame_v.begin()
        while it != self.frame_v.end():
            frame.thisptr = deref(it)
            # we need to update topology since _strip_atoms will modify it
            tmptop = self.top.copy()
            frame._strip_atoms(tmptop, atm, update_top, has_box)
            incr(it)
        if update_top:
            self.top = tmptop.copy()

    #def _strip_atoms_openmp(self, mask=None, bint update_top=True, bint has_box=False):
    def _fast_strip_atoms(self, mask=None, bint update_top=True, bint has_box=False):
        """
        Paramters
        ---------
        mask : str
        update_top : bool, default=True
            'True' : automatically update Topology
        has_box : bool, default=False (does not work with `True` yet)
        Notes
        -----
        * Known bug: 
        * if you use memory for numpy, you need to update after resizing Frame
        >>> arr0 = np.asarray(frame.buffer)
        >>> frame.strip_atoms(top,"!@CA")
        >>> # update view
        >>> arr0 = np.asarray(frame.buffer)
        """
        # NOTE: tested openmp (prange) but don't see the different. Need to 
        # doublecheck if we DID apply openmp correctly

        cdef Frame frame = Frame()
        cdef _Topology _tmptop
        cdef _Topology* _newtop_ptr
        cdef _Frame _tmpframe
        cdef int i 
        cdef int n_frames = self.frame_v.size()
        cdef AtomMask atm = self.top(mask)

        atm.invert_mask() # read note in `Frame._strip_atoms`

        if mask == None: 
            raise ValueError("Must provide mask to strip")
        mask = mask.encode("UTF-8")

        # do not dealloc since we use memoryview for _Frame
        frame.py_free_mem = False

        # TODO : make it even faster by openmp
        # need to handal memory to avoid double-free
        _newtop_ptr = self.top.thisptr.modifyStateByMask(atm.thisptr[0])
        #for i in prange(n_frames, nogil=True):
        for i in range(n_frames):
            # point to i-th _Frame
            frame.thisptr = new _Frame() # make private copy for each core
            frame.thisptr = self.frame_v[i]
            # make a copy and modify it. (Why?)
            # why do we need this?
            # update new _Topology
            # need to copy all other informations
            # allocate
            _tmpframe.SetupFrameV(_newtop_ptr.Atoms(), _newtop_ptr.ParmCoordInfo())
            _tmpframe.SetFrame(frame.thisptr[0], atm.thisptr[0])
            # make a copy: coords, vel, mass...
            # if only care about `coords`, use `_fast_copy_from_frame`
            frame.thisptr[0] = _tmpframe
        if update_top:
            # C++ assignment
            self.top.thisptr[0] = _newtop_ptr[0]

    def save(self, filename="", fmt='unknown', overwrite=True):
        _savetraj(self, filename, fmt, overwrite)

    def write(self, *args, **kwd):
        """same as `save` method"""
        self.save(*args, **kwd)

    def rmsfit_to(self, ref=None, mask="*"):
        """do the fitting to reference Frame by rotation and translation
        Parameters
        ----------
        ref : {Frame object, int, str}, default=None 
            Reference
        mask : str or AtomMask object, default='*' (fit all atoms)

        Examples
        --------
            traj.rmsfit_to(0) # fit to 1st frame
            traj.rmsfit_to('last', '@CA') # fit to last frame using @CA atoms
        """
        # not yet dealed with `mass` and box
        cdef Frame frame
        cdef AtomMask atm
        cdef Frame ref_frame
        cdef int i

        if isinstance(ref, Frame):
            ref_frame = <Frame> ref
        elif is_int(ref):
            i = <int> ref
            ref_frame = self[i]
        elif isinstance(ref, string_types):
            if ref.lower() == 'first':
                i = 0
            if ref.lower() == 'last':
                i = -1
            ref_frame = self[i]
        else:
            raise ValueError("ref must be string, Frame object or integer")

        if isinstance(mask, string_types):
            atm = self.top(mask)
        elif isinstance(mask, AtomMask):
            atm = <AtomMask> mask
        else:
            raise ValueError("mask must be string or AtomMask object")

        for frame in self:
            _, mat, v1, v2 = frame.rmsd(ref_frame, atm, get_mvv=True)
            frame.trans_rot_trans(v1, mat, v2)

    # start copy and paste from "__action_in_traj.py"
    def calc_distance(self, mask="", *args, **kwd):
        return pyca.calc_distance(self, mask, *args, **kwd)

    def calc_distrmsd(self, mask="", *args, **kwd):
        return pyca.calc_distrmsd(self, mask, *args, **kwd)

    def calc_radgyr(self, mask="", *args, **kwd):
        return pyca.calc_radgyr(self, mask, *args, **kwd)

    def calc_angle(self, mask="", *args, **kwd):
        return pyca.calc_angle(self, mask, *args, **kwd)

    def calc_matrix(self, mask=""):
        return pyca.calc_matrix(self, mask)

    def calc_dssp(self, mask="", *args, **kwd):
        return pyca.calc_dssp(self, mask, *args, **kwd)

    def calc_dihedral(self, mask="", *args, **kwd):
        return pyca.calc_dihedral(self, mask, *args, **kwd)

    def calc_multidihedral(self, mask="", *args, **kwd):
        return pyca.calc_multidihedral(self, mask, *args, **kwd)

    def calc_molsurf(self, mask="", *args, **kwd):
        return pyca.calc_molsurf(self, mask, *args, **kwd)

    def calc_center_of_mass(self, mask="", *args, **kwd):
        return pyca.calc_center_of_mass(self, mask, *args, **kwd)

    def calc_COM(self, mask="", *args, **kwd):
        return pyca.calc_center_of_mass(self, mask, *args, **kwd)

    def calc_center_of_geometry(self, mask="", *args, **kwd):
        return pyca.calc_center_of_geometry(self, mask, *args, **kwd)

    def calc_COG(self, mask="", *args, **kwd):
        return pyca.calc_center_of_geometry(self, mask, *args, **kwd)

    def calc_vector(self, mask="", dtype='dataset', *args, **kwd):
        from pytraj.actions.Action_Vector import Action_Vector
        from pytraj.DataSetList import DataSetList
        act = Action_Vector()
        dslist = DataSetList()

        act(mask, self, dslist=dslist)
        return _get_data_from_dtype(dslist, dtype)

    def search_hbonds(self, mask="*", *args, **kwd):
        return pyca.search_hbonds(self, mask, *args, **kwd)

    def get_average_frame(self, mask="", *args, **kwd):
        return pyca.get_average_frame(self, mask, *args, **kwd)

    def calc_watershell(self, mask="", *args, **kwd):
        return pyca.calc_watershell(self, mask, *args, **kwd)

    def autoimage(self, mask=""):
        # NOTE: I tried to used cpptraj's Action_AutoImage directly but
        # there is no gain in speed. don't try.
        pyca.do_autoimage(self, mask)

    def rotate(self, mask=""):
        pyca.do_rotation(self, mask)

    def translate(self, mask=""):
        pyca.do_translation(self, mask)

    def set_nobox(self):
        cdef Frame frame

        for frame in self:
            frame.set_nobox()

    def _allocate(self, int n_frames, int n_atoms):
        """pre-allocate (n_atoms, n_atoms, 3)
        """
        cdef Frame frame

        self.frame_v.resize(n_frames)
        for i in range(n_frames):
            self.frame_v[i] = new _Frame(n_atoms)

    def box_to_ndarray(self):
        return _box_to_ndarray(self)
