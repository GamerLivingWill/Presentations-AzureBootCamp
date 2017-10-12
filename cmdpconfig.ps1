configuration CMDPConfig
{
    # One can evaluate expressions to get the node list
    # E.g: $AllNodes.Where("Role -eq Web").NodeName
    node ("localhost")
    {
        # Call Resource Provider
        # E.g: WindowsFeature, File
        WindowsFeature RemoveUI
        {
            Name = 'Server-Gui-Shell'
            Ensure = 'Absent'
            
        }

    }
}CMDPConfig