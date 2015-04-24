from __future__ import absolute_import, print_function
from pytraj.base import *
from pytraj import io as mdio
from pytraj.utils.check_and_assert import assert_almost_equal
from .data_sample.load_sample_data import load_sample_data
from pytraj import adict
from pytraj.misc import info
from pytraj._set_silent import set_world_silent

def run_tests():
    traj = load_sample_data()

    # test Topology
    #print (traj.top)
    # test FrameArray
    #print (traj)
    # test import action
    print ("all cpptraj actions")
    for key in sorted(adict.keys()):
        print (key)
        # make Action objects
        # not sure why getting " free(): invalid next size (fast)" error
        #adict[key]
        #info(adict[key])
    #print (adict.keys())
    print ("OK")

if __name__ == '__main__':
    run_tests()
