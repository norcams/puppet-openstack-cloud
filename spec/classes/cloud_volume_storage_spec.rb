#
# Copyright (C) 2014 eNovance SAS <licensing@enovance.com>
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#
# Unit tests for cloud::volume::storage class
#

require 'spec_helper'

describe 'cloud::volume::storage' do

  shared_examples_for 'openstack volume storage' do

    let :pre_condition do
      "class { 'cloud::volume':
        cinder_db_host             => '10.0.0.1',
        cinder_db_user             => 'cinder',
        cinder_db_password         => 'secret',
        rabbit_hosts               => ['10.0.0.1'],
        rabbit_password            => 'secret',
        verbose                    => true,
        debug                      => true,
        log_facility               => 'LOG_LOCAL0',
        storage_availability_zone  => 'nova',
        use_syslog                 => true }"
    end

    let :params do
      { :cinder_rbd_pool            => 'ceph_cinder',
        :cinder_rbd_user            => 'cinder',
        :cinder_rbd_secret_uuid     => 'secret',
        :cinder_rbd_max_clone_depth => '10',
        :cinder_backends            => {
          'rbd' => {
            'lowcost' => {
              'rbd_pool'               => 'ceph_cinder',
              'rbd_user'               => 'cinder',
              'rbd_secret_uuid'        => 'secret'
            }
          },
          'netapp' => {
            'premium' => {
              'netapp_server_hostname' => 'netapp-server.host',
              'netapp_login'           => 'joe',
              'netapp_password'        => 'secret'
            }
          },
          'iscsi' => {
            'fast' => {
              'iscsi_ip_address' => '10.0.0.1',
              'volume_group'     => 'fast-vol'
            }
          }
        },
        :ks_keystone_internal_proto => 'http',
        :ks_keystone_internal_port  => '5000',
        :ks_keystone_internal_host  => 'keystone.host',
        :ks_cinder_password         => 'secret' }
    end

    it 'configure cinder common' do
      is_expected.to contain_class('cinder').with(
          :verbose                   => true,
          :debug                     => true,
          :rabbit_userid             => 'cinder',
          :rabbit_hosts              => ['10.0.0.1'],
          :rabbit_password           => 'secret',
          :rabbit_virtual_host       => '/',
          :log_facility              => 'LOG_LOCAL0',
          :use_syslog                => true,
          :log_dir                   => false,
          :storage_availability_zone => 'nova'
        )

      is_expected.to contain_cinder_config('DEFAULT/notification_driver').with('value' => 'cinder.openstack.common.notifier.rpc_notifier')

    end

    it 'checks if Cinder DB is populated' do
      is_expected.to contain_exec('cinder_db_sync').with(
        :command => 'cinder-manage db sync',
        :user    => 'cinder',
        :path    => '/usr/bin',
        :unless  => '/usr/bin/mysql cinder -h 10.0.0.1 -u cinder -psecret -e "show tables" | /bin/grep Tables'
      )
    end

    it 'configure cinder volume service' do
      is_expected.to contain_class('cinder::volume')
    end

    context 'with RBD backend' do
      it 'configures rbd volume driver' do
        is_expected.to contain_cinder_config('lowcost/volume_backend_name').with_value('lowcost')
        is_expected.to contain_cinder_config('lowcost/rbd_pool').with_value('ceph_cinder')
        is_expected.to contain_cinder_config('lowcost/rbd_user').with_value('cinder')
        is_expected.to contain_cinder_config('lowcost/rbd_secret_uuid').with_value('secret')
        is_expected.to contain_cinder_config('lowcost/volume_tmp_dir').with_value('/tmp')
        is_expected.to contain_cinder__type('lowcost').with(
          :set_key        => 'volume_backend_name',
          :set_value      => 'lowcost',
          :os_tenant_name => 'services',
          :os_username    => 'cinder',
          :os_password    => 'secret',
          :os_auth_url    => 'http://keystone.host:5000/v2.0'
        )
        is_expected.to contain_group('cephkeyring').with(:ensure => 'present')
        is_expected.to contain_exec('add-cinder-to-group').with(
          :command => 'usermod -a -G cephkeyring cinder',
          :path    => ['/usr/sbin', '/usr/bin', '/bin', '/sbin'],
          :unless  => 'groups cinder | grep cephkeyring'
        )
      end
    end

    context 'with NetApp backend' do
      it 'configures netapp volume driver' do
        is_expected.to contain_cinder_config('premium/volume_backend_name').with_value('premium')
        is_expected.to contain_cinder_config('premium/netapp_login').with_value('joe')
        is_expected.to contain_cinder_config('premium/netapp_password').with_value('secret')
        is_expected.to contain_cinder_config('premium/netapp_server_hostname').with_value('netapp-server.host')
        is_expected.to contain_cinder__type('premium').with(
          :set_key   => 'volume_backend_name',
          :set_value => 'premium',
          :notify    => 'Service[cinder-volume]'
        )
      end
    end

    context 'with iSCSI backend' do
      it 'configures iSCSI volume driver' do
        is_expected.to contain_cinder_config('fast/volume_backend_name').with_value('fast')
        is_expected.to contain_cinder_config('fast/iscsi_ip_address').with_value('10.0.0.1')
        is_expected.to contain_cinder_config('fast/volume_group').with_value('fast-vol')
        is_expected.to contain_cinder__type('fast').with(
          :set_key   => 'volume_backend_name',
          :set_value => 'fast',
          :notify    => 'Service[cinder-volume]'
        )
      end
    end

    context 'with two RBD backends' do
      before :each do
        params.merge!(
          :cinder_backends => {
            'rbd' => {
              'lowcost' => {
                'rbd_pool'        => 'low',
                'rbd_user'        => 'cinder',
                'rbd_secret_uuid' => 'secret',
              },
              'normal' => {
                'rbd_pool'         => 'normal',
                'rbd_user'         => 'cinder',
                'rbd_secret_uuid'  => 'secret',
              }
            }
          }
        )
      end

      it 'configures two rbd volume backends' do
        is_expected.to contain_cinder_config('lowcost/volume_backend_name').with_value('lowcost')
        is_expected.to contain_cinder_config('lowcost/rbd_pool').with_value('low')
        is_expected.to contain_cinder_config('lowcost/rbd_user').with_value('cinder')
        is_expected.to contain_cinder_config('lowcost/rbd_secret_uuid').with_value('secret')
        is_expected.to contain_cinder_config('lowcost/volume_tmp_dir').with_value('/tmp')
        is_expected.to contain_cinder__type('lowcost').with(
          :set_key        => 'volume_backend_name',
          :set_value      => 'lowcost',
          :os_tenant_name => 'services',
          :os_username    => 'cinder',
          :os_password    => 'secret',
          :os_auth_url    => 'http://keystone.host:5000/v2.0'
        )
        is_expected.to contain_cinder_config('normal/volume_backend_name').with_value('normal')
        is_expected.to contain_cinder_config('normal/rbd_pool').with_value('normal')
        is_expected.to contain_cinder_config('normal/rbd_user').with_value('cinder')
        is_expected.to contain_cinder_config('normal/rbd_secret_uuid').with_value('secret')
        is_expected.to contain_cinder_config('normal/volume_tmp_dir').with_value('/tmp')
        is_expected.to contain_cinder__type('normal').with(
          :set_key        => 'volume_backend_name',
          :set_value      => 'normal',
          :os_tenant_name => 'services',
          :os_username    => 'cinder',
          :os_password    => 'secret',
          :os_auth_url    => 'http://keystone.host:5000/v2.0'
        )
      end
    end

    context 'with all backends enabled' do
      it 'configure all cinder backends' do
        is_expected.to contain_class('cinder::backends').with(
          :enabled_backends => ['lowcost', 'premium', 'fast']
        )
      end
    end

    context 'with backward compatiblity (without multi-backend)' do
      before :each do
        params.merge!(:cinder_backends => false)
      end
      it 'configure rbd volume driver without multi-backend' do
        is_expected.to contain_cinder__backend__rbd('DEFAULT').with(
          :rbd_pool                         => 'ceph_cinder',
          :rbd_user                         => 'cinder',
          :rbd_secret_uuid                  => 'secret',
          :rbd_ceph_conf                    => '/etc/ceph/ceph.conf',
          :rbd_flatten_volume_from_snapshot => false,
          :rbd_max_clone_depth              => '10'
        )
      end
    end
  end

  context 'on Debian platforms' do
    let :facts do
      { :osfamily => 'Debian' }
    end

    it_configures 'openstack volume storage'
  end

  context 'on RedHat platforms' do
    let :facts do
      { :osfamily => 'RedHat' }
    end

    it_configures 'openstack volume storage'
  end

end
