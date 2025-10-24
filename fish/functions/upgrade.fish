function upgrade
	set world "emerge -auDN @world"
	loginctl inhibit $world
	echo "update completed, starting grub configuration"
	grub-mkconfig -o /boot/grub/grub.cfg
end
