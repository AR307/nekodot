//! Kill-on-close Windows job that owns a desktop child process tree.
use anyhow::{anyhow, Result};
use std::{ffi::c_void, mem::size_of, ptr::null};
use windows_sys::Win32::{
    Foundation::{CloseHandle, HANDLE},
    System::JobObjects::{
        AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
        SetInformationJobObject, TerminateJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
    },
};

pub struct Job(HANDLE);
unsafe impl Send for Job {}
unsafe impl Sync for Job {}

impl Job {
    pub fn new() -> Result<Self> {
        unsafe {
            let handle = CreateJobObjectW(null(), null());
            if handle.is_null() {
                return Err(anyhow!("Could not create a process job"));
            }
            let job = Job(handle);
            let mut info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            if SetInformationJobObject(
                handle,
                JobObjectExtendedLimitInformation,
                &info as *const _ as *const c_void,
                size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            ) == 0
            {
                return Err(anyhow!("Could not configure the process job"));
            }
            Ok(job)
        }
    }
    pub fn assign(&self, process: std::os::windows::io::RawHandle) -> Result<()> {
        if unsafe { AssignProcessToJobObject(self.0, process as HANDLE) } == 0 {
            return Err(anyhow!("Could not attach the process to its job"));
        }
        Ok(())
    }
    pub fn terminate(&self) {
        unsafe {
            TerminateJobObject(self.0, 1);
        }
    }
}

impl Drop for Job {
    fn drop(&mut self) {
        unsafe {
            CloseHandle(self.0);
        }
    }
}
