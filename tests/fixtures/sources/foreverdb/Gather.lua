local _, ns = ...
-- ForeverDB gathering data (tools/build_addon_gathering.py). Do not edit by hand.
-- c = Classic spawn points (CMaNGOS classic-db, GPL-3.0: Classic data, may differ in Forever);
-- f = points players saw in WoW Forever (the Companion); fish = Classic fishing skill for the zone;
-- sk for skinning and the skill colours: ForeverDB's assumption (Classic's rule).
-- Points: 4 base-36 characters each (x then y, tenths of a percent).
ns.gatherData = {
  v = 1, built = "2026-10-05",
  kinds = {
    [1] = { n = "Serpentbloom", p = "herb", sk = 0, item = 5339, ic = 134183, o = { 13891 } },
    [2] = { n = "Peacebloom", p = "herb", sk = 1, item = 2447, ic = 133939, o = { 1618, 3724 } },
    [3] = { n = "Silverleaf", p = "herb", sk = 1, item = 765, ic = 134190, o = { 1617, 3725 } },
    [4] = { n = "Earthroot", p = "herb", sk = 15, item = 2449, ic = 134187, o = { 1619, 3726 } },
    [5] = { n = "Mageroyal", p = "herb", sk = 50, item = 785, ic = 133436, o = { 1620, 3727 } },
    [6] = { n = "Briarthorn", p = "herb", sk = 70, item = 2450, ic = 134412, o = { 1621, 3729 } },
    [45] = { n = "Adult Plainstrider", p = "skin", sk = 1, lv = { 6, 7 }, npc = { 2956 } },
    [47] = { n = "Armored Scorpid", p = "skin", sk = 1, lv = { 7, 8 }, npc = { 3126 } },
    [52] = { n = "Bloodtalon Taillasher", p = "skin", sk = 1, lv = { 6, 8 }, npc = { 3122 } },
  },
  zones = {
    [1411] = { fish = 25, k = {
      [5] = { c = "0r97159v179u1aa41j8f1k861n8c1n8e209z23ab4b9o5eav5l8b5m7v5m8j5p835p8b5p8q5t7s5t8b5u8o5w825xb66093618q618u65ar699f6ha28rax909x928g9c819c9h9d9b9d9uaofiax6xb87ubbe5bt7fc06ocadscbdrdh9he27deb5cef6mf16dg34qg588", f = "", w = 5.6 },
      [6] = { c = "079u1q834j8v5g80669ra4q9a7k6", f = "", w = 2.3 },
      [47] = { c = "9xaea6aaadbeag9gahbtajcxau9xawbpb6cybbasbcb8bfedbgdrbn80bxdgc290c39gc4cpcecdck7ucl7dcn8qcoczd49vd8a9di8idkade15fe260e6ahe74yeo5ef49ef8a6fg68fh8tfp82g08lg17zg26xg86h", f = "", w = 63 },
      [52] = { c = "azefb8d3b9amba9mbgdzbrdnc59gc6cscyaadpaadq5ce09uf88rf99lfdadfl84fr72g072g07xg46fginbgnoogrmygzlsh8qrhjq8hskjhso4hwn2itmdiuoiiwjqj0nbj2krj8mtjekrjgjn", f = "gkn0", w = 60 },
    } },
    [1412] = { fish = 25, k = {
      [2] = { c = "9xdgadcnagceame4ao7jas6naud6az61bei6bjj2bqfgc1d2c1emc55tcg7kcmdocsf0d35xd873dtb5dud8dy7zdzb7e35ye56ne5jkef7kegdwekc9eqimer8hevh9f0dvfaeefaekfmgnfn8mfshpgeh2gik1gjj1ind7iz22j2c3jdcsjf3wjtg8k5f9liek", f = "", w = 7.3 },
      [4] = { c = "8k9n9jd39pelad6iau5gcnkcd1kpe0kae7kue95ieikwel5yer7hewkzf57qfbdpfeb7frdzfwahfyehg08kg3fqge88h94yhh4aht4jhv4nhz4ehz5ki04ri04ui14fi34qi35yiv6qix22ix6rix8fiy9rj06lj17vj31jj36ijc1zjh1rjh1xjoehjt0ek3e4", f = "", w = 8.6 },
      [5] = { c = "hs4gil46ite8ix0lix97j099j304j37dj48zj50ej59gja0rje60je8ije92ji0sjkbdjm0kjn0njo11jo6pjo9ijqd8jr9cjs9mjuf2k17lkfdol7ecmffgmvdpn1f7n5dln6fenbe5nddhnedinkdnnke6nudsnve1o6dgqqfa", f = "", w = 7.7 },
      [6] = { c = "as0fhx5jid54ix0lj283jaapjaffjg2ljm1ijrdojrg7jx2ak19gk5eil8f8mddznje9oldspodxqadnqfehr5dz", f = "", w = 5.2 },
      [45] = { c = "a7cha8dxaad0bcfkbehubfknbgjkblidboj2bphhbxgfbyjbc3dwc3flc3kac7cwclcacmk6cxjidaeadbcydcj2dlj7e4e4e4hqeghyemdeemjkeqc7eqh2ercyevecf8dmf9c8fcjaffgyffj4fhejfikfg9highgd", f = "", w = 52 },
    } },
  },
}
