import React from 'react'
import { shallow } from 'enzyme'

import List from 'pages/DataSources/List/List'

const f = _ => _

describe('DataSources/List: default props for items', () => {

  it('should render 2 spans for 2 items', () => {
    const items = [{ id: 1, name: '1' }, { id: 2, name: '2' }]

    const wrapper = shallow(<List fetchData={f} items={items} />)

    expect(wrapper.find('span').length).toBe(items.length)
  })
})
