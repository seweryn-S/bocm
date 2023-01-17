# bocm
BlueOcean control manager.

Automatyczne, konfigurowalne budowanie systemu na podstawie wskazanego obrazu.
Obrazy pobierane przy pomocy rclone, współpracuje więc z większością popularnych chmur.

####################################################################################################
# UWAGA dotyczaca pliku partitions.yml!
#
# Partycje są montowane w kolejności występowania w pliku, nie w kolejności numeracji
# Mozna wpisać do pliku w kolejności nie rosnącej numeracji, czyli np partycja 2 moze być przed 1
#
# Przyklad: Jeśli pratycja 1 to /boot/EFI a partycja 2 to /boot 
#          partycja 2 musi występować w pliku przez partycją 1
####################################################################################################