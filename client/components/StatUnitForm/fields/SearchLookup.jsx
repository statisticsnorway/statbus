import React from 'react'

import SearchField from 'components/Search/SearchField'
import { internalRequest } from 'helpers/request'


const { func, shape, string, oneOfType, number } = React.PropTypes

class SearchLookup extends React.Component {

  static propTypes = {
    searchData: shape(),
    value: oneOfType([number, string]),
    name: string.isRequired,
    onChange: func.isRequired,
  }

  static defaultProps = {
    searchData: [],
    value: '',
    lookup: '',
    errors: [],
  }

  state = {
    lookup: '',
  }

  // componentDidMount() {
  //   const { value, searchData } = this.porps

  //   if (value !== null || value !== undefined || value !== '') {
  //     internalRequest({
  //       url: `${searchData.editUrl}${value}`,
  //       method: 'get',
  //       onSuccess: (lookup) => {
  //         console.log(lookup)
  //         this.setState({ lookup }) },
  //     })
  //   }
  // }

  setLookupValue = (data) => {
    const { name } = this.props
    const value = data.id
    this.props.onChange({ name, value })
  }

  render() {
    const { searchData, value } = this.props
    console.log('adfasdf', value)
    return (
      <SearchField
        searchData={searchData}
        onValueSelected={this.setLookupValue}
      />
    )
  }
}

export default SearchLookup
