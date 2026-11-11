Module Program
    Function Main(ByVal args As String()) As Integer
        System.Console.WriteLine("OK:" & String.Join("|", args))
        Return 3
    End Function
End Module
