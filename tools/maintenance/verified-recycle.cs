using System;
using System.Runtime.InteropServices;
public static class VerifiedRecycle {
 [ComImport, Guid("3AD05575-8857-4850-9277-11B85BDB8E09")] class FileOperation {}
 [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IShellItem {}
 [ComImport, Guid("947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IFileOperation {
 void Advise(IntPtr sink,out uint cookie); void Unadvise(uint cookie);
 void SetOperationFlags(uint flags); void SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)] string msg);
 void SetProgressDialog(IntPtr dialog); void SetProperties(IntPtr props); void SetOwnerWindow(IntPtr hwnd);
 void ApplyPropertiesToItem(IntPtr item); void ApplyPropertiesToItems(IntPtr items);
 void RenameItem(IntPtr item,IntPtr name,IntPtr sink); void RenameItems(IntPtr items,IntPtr name);
 void MoveItem(IntPtr item,IntPtr dest,IntPtr name,IntPtr sink); void MoveItems(IntPtr items,IntPtr dest);
 void CopyItem(IntPtr item,IntPtr dest,IntPtr name,IntPtr sink); void CopyItems(IntPtr items,IntPtr dest);
 void DeleteItem(IShellItem item,IntPtr sink); void DeleteItems(IntPtr items);
 void NewItem(IntPtr dest,uint attributes,IntPtr name,IntPtr template,IntPtr sink);
 void PerformOperations(); void GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)] out bool aborted);
 }
 [DllImport("shell32.dll",CharSet=CharSet.Unicode,PreserveSig=false)] static extern void SHCreateItemFromParsingName(string path,IntPtr bind,ref Guid iid,out IShellItem item);
 public static void Recycle(string path) {
   Guid iid = new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"); IShellItem item;
   SHCreateItemFromParsingName(path,IntPtr.Zero,ref iid,out item);
   IFileOperation op=(IFileOperation)new FileOperation();
   try {
     // RECYCLEONDELETE + EARLYFAILURE; WANTNUKEWARNING must never be accepted
     // as a permanent-delete fallback. Callers also verify quota and $I/$R.
     op.SetOperationFlags(0x00080000u | 0x00100000u | 0x20000000u | 0x00000400u | 0x00000004u | 0x00000010u | 0x00004000u);
     op.DeleteItem(item,IntPtr.Zero); op.PerformOperations(); bool aborted; op.GetAnyOperationsAborted(out aborted);
     if(aborted) throw new Exception("Recycle operation aborted");
   } finally {Marshal.ReleaseComObject(op); Marshal.ReleaseComObject(item);}
 }
}
